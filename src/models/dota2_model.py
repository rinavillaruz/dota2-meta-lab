# dota2_model.py
"""
Dota 2 Meta Analysis Model
"""

import os
import numpy as np
import tensorflow as tf
from tensorflow import keras
from sklearn.preprocessing import StandardScaler
from datetime import datetime
from typing import Dict, Optional
import logging

logger = logging.getLogger(__name__)


class Dota2MetaModel:
    """
    Neural network model for Dota 2 match outcome prediction
    """
    
    def __init__(self, num_heroes: int = 130):
        """
        Initialize model
        
        Args:
            num_heroes: Number of heroes in Dota 2
        """
        self.num_heroes = num_heroes
        self.model: Optional[keras.Model] = None
        self.scaler = StandardScaler()
        self.history = None
    
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
        logger.info(f"Training on {len(X_train)} samples")
        logger.info(f"Validating on {len(X_val)} samples")
        
        # Scale features
        X_train_scaled = self.scaler.fit_transform(X_train)
        X_val_scaled = self.scaler.transform(X_val)
        
        # Build model if not already built
        if self.model is None:
            self.model = self.build_model(X_train.shape[1])
        
        # Callbacks
        callbacks = [
            keras.callbacks.EarlyStopping(
                monitor='val_loss',
                patience=10,
                restore_best_weights=True,
                verbose=1
            ),
            keras.callbacks.ReduceLROnPlateau(
                monitor='val_loss',
                factor=0.5,
                patience=5,
                min_lr=1e-6,
                verbose=1
            ),
            keras.callbacks.TensorBoard(
                log_dir=f'./logs/fit/{datetime.now().strftime("%Y%m%d-%H%M%S")}'
            )
        ]
        
        # Train
        self.history = self.model.fit(
            X_train_scaled,
            y_train,
            validation_data=(X_val_scaled, y_val),
            epochs=epochs,
            batch_size=batch_size,
            callbacks=callbacks,
            verbose=1
        )
        
        logger.info("Training complete!")
        return self.history
    
    def evaluate(self, X_test: np.ndarray, y_test: np.ndarray) -> Dict[str, float]:
        """
        Evaluate model performance
        
        Args:
            X_test: Test features
            y_test: Test labels
            
        Returns:
            Dictionary of metrics
        """
        if self.model is None:
            raise ValueError("Model not trained yet!")
        
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
    
    def predict(self, X: np.ndarray) -> np.ndarray:
        """
        Make predictions
        
        Args:
            X: Features to predict on
            
        Returns:
            Predictions as numpy array
        """
        if self.model is None:
            raise ValueError("Model not trained yet!")
        
        X_scaled = self.scaler.transform(X)
        return self.model.predict(X_scaled, verbose=0)
    
    def save_model(self, model_dir: str = './models') -> str:
        """
        Save trained model
        
        Args:
            model_dir: Directory to save model
            
        Returns:
            Path to saved model
        """
        if self.model is None:
            raise ValueError("No model to save!")
        
        os.makedirs(model_dir, exist_ok=True)
        
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        model_path = os.path.join(model_dir, f'dota2_meta_model_{timestamp}')
        
        # Save model
        self.model.save(model_path)
        logger.info(f"Model saved to {model_path}")
        
        # Save scaler
        import joblib
        scaler_path = os.path.join(model_dir, f'scaler_{timestamp}.pkl')
        joblib.dump(self.scaler, scaler_path)
        logger.info(f"Scaler saved to {scaler_path}")
        
        return model_path
    
    def load_model(self, model_path: str, scaler_path: str):
        """
        Load a saved model
        
        Args:
            model_path: Path to saved model
            scaler_path: Path to saved scaler
        """
        logger.info(f"Loading model from {model_path}")
        self.model = keras.models.load_model(model_path)
        
        logger.info(f"Loading scaler from {scaler_path}")
        import joblib
        self.scaler = joblib.load(scaler_path)
        
        logger.info("Model and scaler loaded successfully!")