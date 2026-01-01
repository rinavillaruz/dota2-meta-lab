"""
Train ML model to predict Dota 2 match outcomes
Usage: python scripts/train_model.py
"""
import pandas as pd
import numpy as np
import tensorflow as tf
from tensorflow import keras
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import StandardScaler
import joblib
import os
import json
from datetime import datetime

class Dota2ModelTrainer:
    def __init__(self, data_file='data/processed_matches.csv'):
        """Initialize trainer with processed data"""
        print(f"📚 Loading processed data from {data_file}...")
        
        self.df = pd.read_csv(data_file)
        print(f"✅ Loaded {len(self.df)} matches")
        
        self.model = None
        self.scaler = None
        self.history = None
    
    def prepare_data(self, test_size=0.2):
        """Prepare data for training"""
        print("\n🔧 Preparing data for training...")
        
        # Features: hero picks and team stats
        feature_cols = [
            'radiant_hero_1', 'radiant_hero_2', 'radiant_hero_3', 'radiant_hero_4', 'radiant_hero_5',
            'dire_hero_1', 'dire_hero_2', 'dire_hero_3', 'dire_hero_4', 'dire_hero_5',
            'duration', 'radiant_kills', 'dire_kills', 
            'radiant_gold', 'dire_gold', 'radiant_xp', 'dire_xp'
        ]
        
        X = self.df[feature_cols].values
        y = self.df['radiant_win'].values
        
        # Split data
        X_train, X_test, y_train, y_test = train_test_split(
            X, y, test_size=test_size, random_state=42
        )
        
        # Scale features
        self.scaler = StandardScaler()
        X_train_scaled = self.scaler.fit_transform(X_train)
        X_test_scaled = self.scaler.transform(X_test)
        
        print(f"✅ Data prepared:")
        print(f"   Training samples: {len(X_train)}")
        print(f"   Test samples: {len(X_test)}")
        print(f"   Features: {len(feature_cols)}")
        print(f"   Radiant win rate: {y.mean()*100:.1f}%")
        
        return X_train_scaled, X_test_scaled, y_train, y_test
    
    def build_model(self, input_dim):
        """Build neural network model"""
        print("\n🏗️  Building neural network...")
        
        model = keras.Sequential([
            # Input layer
            keras.layers.Dense(128, activation='relu', input_dim=input_dim),
            keras.layers.Dropout(0.3),
            
            # Hidden layers
            keras.layers.Dense(64, activation='relu'),
            keras.layers.Dropout(0.3),
            
            keras.layers.Dense(32, activation='relu'),
            keras.layers.Dropout(0.2),
            
            # Output layer (binary classification)
            keras.layers.Dense(1, activation='sigmoid')
        ])
        
        model.compile(
            optimizer='adam',
            loss='binary_crossentropy',
            metrics=['accuracy', tf.keras.metrics.AUC(name='auc')]
        )
        
        print("✅ Model architecture:")
        model.summary()
        
        return model
    
    def train(self, X_train, X_test, y_train, y_test, epochs=50, batch_size=32):
        """Train the model"""
        print(f"\n🚀 Training model for {epochs} epochs...")
        
        # Build model
        self.model = self.build_model(input_dim=X_train.shape[1])
        
        # Callbacks
        early_stop = keras.callbacks.EarlyStopping(
            monitor='val_loss',
            patience=10,
            restore_best_weights=True
        )
        
        reduce_lr = keras.callbacks.ReduceLROnPlateau(
            monitor='val_loss',
            factor=0.5,
            patience=5,
            min_lr=0.00001
        )
        
        # Train
        self.history = self.model.fit(
            X_train, y_train,
            validation_data=(X_test, y_test),
            epochs=epochs,
            batch_size=batch_size,
            callbacks=[early_stop, reduce_lr],
            verbose=1
        )
        
        print("\n✅ Training complete!")
    
    def evaluate(self, X_test, y_test):
        """Evaluate model performance"""
        print("\n📊 Evaluating model...")
        
        # Get predictions
        y_pred_proba = self.model.predict(X_test)
        y_pred = (y_pred_proba > 0.5).astype(int)
        
        # Calculate metrics
        loss, accuracy, auc = self.model.evaluate(X_test, y_test, verbose=0)
        
        # Confusion matrix
        from sklearn.metrics import confusion_matrix, classification_report
        
        cm = confusion_matrix(y_test, y_pred)
        
        print(f"\n📈 Model Performance:")
        print(f"   Accuracy: {accuracy*100:.2f}%")
        print(f"   AUC: {auc:.4f}")
        print(f"   Loss: {loss:.4f}")
        
        print(f"\n🎯 Confusion Matrix:")
        print(f"   True Negatives (Dire wins): {cm[0][0]}")
        print(f"   False Positives: {cm[0][1]}")
        print(f"   False Negatives: {cm[1][0]}")
        print(f"   True Positives (Radiant wins): {cm[1][1]}")
        
        print(f"\n📋 Classification Report:")
        print(classification_report(y_test, y_pred, target_names=['Dire Win', 'Radiant Win']))
        
        return {
            'accuracy': float(accuracy),
            'auc': float(auc),
            'loss': float(loss)
        }
    
    def save_model(self, model_dir='models'):
        """Save trained model and scaler"""
        print(f"\n💾 Saving model to {model_dir}/...")
        
        os.makedirs(model_dir, exist_ok=True)
        
        # Save model
        model_path = os.path.join(model_dir, 'dota2_model.h5')
        self.model.save(model_path)
        print(f"   ✅ Model saved: {model_path}")
        
        # Save scaler
        scaler_path = os.path.join(model_dir, 'scaler.pkl')
        joblib.dump(self.scaler, scaler_path)
        print(f"   ✅ Scaler saved: {scaler_path}")
        
        # Save metadata
        metadata = {
            'trained_at': datetime.now().isoformat(),
            'num_matches': len(self.df),
            'model_architecture': 'Sequential Neural Network',
            'input_features': [
                'radiant_hero_1', 'radiant_hero_2', 'radiant_hero_3', 'radiant_hero_4', 'radiant_hero_5',
                'dire_hero_1', 'dire_hero_2', 'dire_hero_3', 'dire_hero_4', 'dire_hero_5',
                'duration', 'radiant_kills', 'dire_kills', 
                'radiant_gold', 'dire_gold', 'radiant_xp', 'dire_xp'
            ]
        }
        
        metadata_path = os.path.join(model_dir, 'metadata.json')
        with open(metadata_path, 'w') as f:
            json.dump(metadata, f, indent=2)
        print(f"   ✅ Metadata saved: {metadata_path}")

def main():
    print("=" * 60)
    print("🤖 DOTA2 Meta Lab - Model Trainer")
    print("=" * 60)
    
    # Initialize trainer
    trainer = Dota2ModelTrainer('data/processed_matches.csv')
    
    # Prepare data
    X_train, X_test, y_train, y_test = trainer.prepare_data(test_size=0.2)
    
    # Train model
    trainer.train(X_train, X_test, y_train, y_test, epochs=50, batch_size=32)
    
    # Evaluate
    metrics = trainer.evaluate(X_test, y_test)
    
    # Save model
    trainer.save_model('models')
    
    print("\n" + "=" * 60)
    print("✅ Model training complete!")
    print(f"   Final Accuracy: {metrics['accuracy']*100:.2f}%")
    print(f"   AUC Score: {metrics['auc']:.4f}")
    print("=" * 60)
    print("\nNext step: python scripts/store_database.py")

if __name__ == "__main__":
    main()