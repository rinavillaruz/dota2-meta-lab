"""
DOTA2 Meta Lab - Prediction API
"""
from flask import Flask, request, jsonify
import tensorflow as tf
import joblib
import numpy as np
import os
from pymongo import MongoClient

app = Flask(__name__)

# Load model and scaler on startup
MODEL_PATH = os.getenv('MODEL_DIR', 'models') + '/dota2_model.h5'
SCALER_PATH = os.getenv('MODEL_DIR', 'models') + '/scaler.pkl'

print(f"🤖 Loading model from {MODEL_PATH}...")
model = None
scaler = None

try:
    if os.path.exists(MODEL_PATH):
        model = tf.keras.models.load_model(MODEL_PATH)
        scaler = joblib.load(SCALER_PATH)
        print(f"✅ Model loaded successfully!")
    else:
        print(f"⚠️  Model not found at {MODEL_PATH}")
except Exception as e:
    print(f"❌ Error loading model: {e}")

# MongoDB connection
mongo_client = MongoClient('mongodb://localhost:27017/')
db = mongo_client['dota2_meta_lab']

@app.route('/')
def index():
    """Home page"""
    return jsonify({
        'service': 'DOTA2 Meta Lab API',
        'version': '1.0.0',
        'status': 'running',
        'endpoints': {
            '/health': 'Health check',
            '/predict': 'Predict match outcome (POST)',
            '/stats': 'Database statistics',
            '/heroes': 'Hero statistics'
        }
    })

@app.route('/health')
def health():
    """Health check endpoint"""
    return jsonify({
        'status': 'healthy',
        'model_loaded': model is not None,
        'database_connected': True
    }), 200

@app.route('/predict', methods=['POST'])
def predict():
    """Predict match outcome based on hero picks"""
    if model is None:
        return jsonify({'error': 'Model not loaded'}), 500
    
    try:
        data = request.json
        
        # Extract features
        features = np.array([[
            data.get('radiant_hero_1', 0),
            data.get('radiant_hero_2', 0),
            data.get('radiant_hero_3', 0),
            data.get('radiant_hero_4', 0),
            data.get('radiant_hero_5', 0),
            data.get('dire_hero_1', 0),
            data.get('dire_hero_2', 0),
            data.get('dire_hero_3', 0),
            data.get('dire_hero_4', 0),
            data.get('dire_hero_5', 0),
            data.get('duration', 1800),
            data.get('radiant_kills', 0),
            data.get('dire_kills', 0),
            data.get('radiant_gold', 0),
            data.get('dire_gold', 0),
            data.get('radiant_xp', 0),
            data.get('dire_xp', 0)
        ]])
        
        # Scale features
        features_scaled = scaler.transform(features)
        
        # Predict
        prediction = model.predict(features_scaled, verbose=0)[0][0]
        
        return jsonify({
            'radiant_win_probability': float(prediction),
            'dire_win_probability': float(1 - prediction),
            'predicted_winner': 'Radiant' if prediction > 0.5 else 'Dire',
            'confidence': float(max(prediction, 1 - prediction))
        })
        
    except Exception as e:
        return jsonify({'error': str(e)}), 400

@app.route('/stats')
def stats():
    """Get database statistics"""
    try:
        total_matches = db.matches.count_documents({})
        radiant_wins = db.matches.count_documents({'radiant_win': True})
        
        return jsonify({
            'total_matches': total_matches,
            'radiant_wins': radiant_wins,
            'dire_wins': total_matches - radiant_wins,
            'radiant_win_rate': (radiant_wins / total_matches * 100) if total_matches > 0 else 0
        })
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/heroes')
def heroes():
    """Get hero statistics"""
    try:
        pipeline = [
            {'$unwind': '$players'},
            {'$group': {
                '_id': '$players.hero_id',
                'games': {'$sum': 1},
                'avg_kills': {'$avg': '$players.kills'},
                'avg_deaths': {'$avg': '$players.deaths'},
                'avg_assists': {'$avg': '$players.assists'}
            }},
            {'$sort': {'games': -1}},
            {'$limit': 20}
        ]
        
        heroes = list(db.matches.aggregate(pipeline))
        
        return jsonify({
            'heroes': [
                {
                    'hero_id': h['_id'],
                    'games': h['games'],
                    'avg_kills': round(h['avg_kills'], 2),
                    'avg_deaths': round(h['avg_deaths'], 2),
                    'avg_assists': round(h['avg_assists'], 2)
                }
                for h in heroes
            ]
        })
    except Exception as e:
        return jsonify({'error': str(e)}), 500

if __name__ == '__main__':
    port = int(os.getenv('PORT', 8080))
    app.run(host='0.0.0.0', port=port, debug=True)