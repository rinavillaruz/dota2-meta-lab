#!/usr/bin/env python3
"""
Dota 2 Meta Tracker - TensorFlow Training
Trains a model to predict match outcomes based on hero picks
"""

import os
import json
import numpy as np
import tensorflow as tf
from tensorflow import keras
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import StandardScaler
import logging
from typing import Tuple, List, Dict
from datetime import datetime

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class Dota2MetaModel:
    """Dota 2 Meta Analysis Model"""
    
    def __init__(self, num_heroes: int = 130):
        """
        Initialize model
        
        Args:
            num_heroes: Number of heroes in Dota 2
        """
        self.num_heroes = num_heroes
        self.model = None
        self.scaler = StandardScaler()
        self.hero_id_map = {}
    
    def load_data(self, data_dir: str) -> Tuple[np.ndarray, np.ndarray]:
        """
        Load and preprocess match data
        
        Args:
            data_dir: Directory containing JSON data files
            
        Returns:
            Features and labels as numpy arrays
        """
        logger.info(f"Loading data from {data_dir}")
        
        # Load pro matches
        pro_matches_file = os.path.join(data_dir, 'pro_matches.json')
        with open(pro_matches_file, 'r') as f:
            matches = json.load(f)
        
        logger.info(f"Loaded {len(matches)} matches")
        
        # Extract features and labels
        features = []
        labels = []
        
        for match in matches:
            # Create feature vector: one-hot encoding of picked heroes
            feature = self._create_feature_vector(match)
            label = 1 if match.get('radiant_win', False) else 0
            
            features.append(feature)
            labels.append(label)
        
        X = np.array(features)
        y = np.array(labels)
        
        logger.info(f"Prepared {len(X)} training examples")
        logger.info(f"Feature shape: {X.shape}")
        logger.info(f"Radiant win rate: {np.mean(y):.2%}")
        
        return X, y
    
    def _create_feature_vector(self, match: Dict) -> np.ndarray:
        """
        Create feature vector from match data
        
        Args:
            match: Match data dictionary
            
        Returns:
            Feature vector
        """
        # Simple one-hot encoding for radiant and dire heroes
        # In real implementation, you'd parse pick/ban data
        feature = np.zeros(self.num_heroes * 2)  # *2 for radiant and dire
        
        # This is a simplified example
        # You would extract actual hero picks from match data
        radiant_team = match.get('radiant_team_id', 0) % self.num_heroes
        dire_team = match.get('dire_team_id', 0) % self.num_heroes
        
        feature[radiant_team] = 1  # Radiant pick
        feature[self.num_heroes + dire_team] = 1  # Dire pick
        
        return feature
    
    def build_model(self, input_shape: int) -> keras.Model:
        """
        Build neural network model
        
        Args:
            input_shape: Number of input features
            
        Returns:
            Compiled Keras model
        """
        logger.info("Building model...")
        
        model = keras.Sequential([
            keras.layers.Dense(256, activation='relu', input_shape=(input_shape,)),
            keras.layers.Dropout(0.3),
            keras.layers.Dense(128, activation='relu'),
            keras.layers.Dropout(0.3),
            keras.layers.Dense(64, activation='relu'),
            keras.layers.Dropout(0.2),
            keras.layers.Dense(32, activation='relu'),
            keras.layers.Dense(1, activation='sigmoid')
        ])
        
        model.compile(
            optimizer='adam',
            loss='binary_crossentropy',
            metrics=['accuracy', keras.metrics.AUC(name='auc')]
        )
        
        logger.info("Model architecture:")
        model.summary(print_fn=logger.info)
        
        return model
    
    def train(
        self,
        X_train: np.ndarray,
        y_train: np.ndarray,
        X_val: np.ndarray,
        y_val: np.ndarray,
        epochs: int = 50,
        batch_size: int = 32
    ) -> keras.callbacks.History:
        """
        Train the model
        
        Args:
            X_train: Training features
            y_train: Training labels
            X_val: Validation features
            y_val: Validation labels
            epochs: Number of training epochs
            batch_size: Batch size
            
        Returns:
            Training history
        """
        logger.info("Starting training...")
        
        # Scale features
        X_train_scaled = self.scaler.fit_transform(X_train)
        X_val_scaled = self.scaler.transform(X_val)
        
        # Build model
        self.model = self.build_model(X_train.shape[1])
        
        # Callbacks
        callbacks = [
            keras.callbacks.EarlyStopping(
                monitor='val_loss',
                patience=10,
                restore_best_weights=True
            ),
            keras.callbacks.ReduceLROnPlateau(
                monitor='val_loss',
                factor=0.5,
                patience=5,
                min_lr=1e-6
            ),
            keras.callbacks.TensorBoard(
                log_dir=f'./logs/fit/{datetime.now().strftime("%Y%m%d-%H%M%S")}'
            )
        ]
        
        # Train
        history = self.model.fit(
            X_train_scaled,
            y_train,
            validation_data=(X_val_scaled, y_val),
            epochs=epochs,
            batch_size=batch_size,
            callbacks=callbacks,
            verbose=1
        )
        
        return history
    
    def evaluate(self, X_test: np.ndarray, y_test: np.ndarray) -> Dict[str, float]:
        """
        Evaluate model performance
        
        Args:
            X_test: Test features
            y_test: Test labels
            
        Returns:
            Dictionary of metrics
        """
        logger.info("Evaluating model...")
        
        X_test_scaled = self.scaler.transform(X_test)
        results = self.model.evaluate(X_test_scaled, y_test, verbose=0)
        
        metrics = {
            'loss': results[0],
            'accuracy': results[1],
            'auc': results[2]
        }
        
        logger.info(f"Test Loss: {metrics['loss']:.4f}")
        logger.info(f"Test Accuracy: {metrics['accuracy']:.4f}")
        logger.info(f"Test AUC: {metrics['auc']:.4f}")
        
        return metrics
    
    def save_model(self, model_dir: str = './models'):
        """
        Save trained model
        
        Args:
            model_dir: Directory to save model
        """
        os.makedirs(model_dir, exist_ok=True)
        
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        model_path = os.path.join(model_dir, f'dota2_meta_model_{timestamp}')
        
        self.model.save(model_path)
        logger.info(f"Model saved to {model_path}")
        
        # Save scaler
        import joblib
        scaler_path = os.path.join(model_dir, f'scaler_{timestamp}.pkl')
        joblib.dump(self.scaler, scaler_path)
        logger.info(f"Scaler saved to {scaler_path}")
        
        return model_path


def main():
    """Main training function"""
    
    logger.info("🚀 Starting Dota 2 Meta Tracker Training")
    logger.info(f"TensorFlow version: {tf.__version__}")
    
    # Configuration
    DATA_DIR = os.getenv('DATA_DIR', './data/latest')
    MODEL_DIR = os.getenv('MODEL_DIR', './models')
    EPOCHS = int(os.getenv('EPOCHS', '50'))
    BATCH_SIZE = int(os.getenv('BATCH_SIZE', '32'))
    
    # Initialize model
    model = Dota2MetaModel()
    
    # Load data
    try:
        X, y = model.load_data(DATA_DIR)
    except FileNotFoundError as e:
        logger.error(f"Data files not found: {e}")
        logger.error("Please run fetch_opendota_data.py first!")
        return
    
    # Split data
    X_train, X_temp, y_train, y_temp = train_test_split(
        X, y, test_size=0.3, random_state=42
    )
    X_val, X_test, y_val, y_test = train_test_split(
        X_temp, y_temp, test_size=0.5, random_state=42
    )
    
    logger.info(f"Train set: {len(X_train)} samples")
    logger.info(f"Validation set: {len(X_val)} samples")
    logger.info(f"Test set: {len(X_test)} samples")
    
    # Train model
    history = model.train(
        X_train, y_train,
        X_val, y_val,
        epochs=EPOCHS,
        batch_size=BATCH_SIZE
    )
    
    # Evaluate on test set
    metrics = model.evaluate(X_test, y_test)
    
    # Save model
    model_path = model.save_model(MODEL_DIR)
    
    # Print summary
    print("\n" + "="*50)
    print("Training Summary")
    print("="*50)
    print(f"Test Accuracy: {metrics['accuracy']:.2%}")
    print(f"Test AUC: {metrics['auc']:.4f}")
    print(f"Model saved to: {model_path}")
    print("="*50)
    
    logger.info("✅ Training complete!")


if __name__ == "__main__":
    main()