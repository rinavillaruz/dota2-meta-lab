#!/usr/bin/env python3
"""
Train Dota 2 meta prediction model
Usage: python scripts/train.py
"""

import sys
from pathlib import Path

# Add project root to path
project_root = Path(__file__).parent.parent
sys.path.insert(0, str(project_root))

import tensorflow as tf
from sklearn.model_selection import train_test_split

from src.data import DataLoader
from src.models import Dota2MetaModel, FeatureEngineer
from src.utils import Config, setup_logging

logger = setup_logging(level=Config.LOG_LEVEL)


def main():
    """Main training function"""
    
    logger.info("🚀 Starting Dota 2 Meta Tracker Training")
    logger.info(f"TensorFlow version: {tf.__version__}")
    logger.info(f"Training configuration:")
    logger.info(f"  - Data Dir: {Config.DATA_DIR}")
    logger.info(f"  - Model Dir: {Config.MODEL_DIR}")
    logger.info(f"  - Epochs: {Config.EPOCHS}")
    logger.info(f"  - Batch Size: {Config.BATCH_SIZE}")
    
    try:
        # Initialize components
        logger.info("Initializing components...")
        data_loader = DataLoader(Config.DATA_DIR)
        feature_engineer = FeatureEngineer(num_heroes=Config.NUM_HEROES)
        model = Dota2MetaModel(num_heroes=Config.NUM_HEROES)
        
        # Load data
        logger.info("Loading data...")
        matches = data_loader.load_pro_matches()
        heroes = data_loader.load_heroes()
        
        # Build hero mapping (optional, for interpretability)
        if heroes:
            feature_engineer.build_hero_mapping(heroes)
        
        # Extract features and labels
        X, y = feature_engineer.extract_features_and_labels(matches)
        
        # Split data
        logger.info("Splitting data...")
        X_train, X_temp, y_train, y_temp = train_test_split(
            X, y, 
            test_size=(Config.VALIDATION_SPLIT + Config.TEST_SPLIT),
            random_state=Config.RANDOM_SEED
        )
        
        X_val, X_test, y_val, y_test = train_test_split(
            X_temp, y_temp,
            test_size=(Config.TEST_SPLIT / (Config.VALIDATION_SPLIT + Config.TEST_SPLIT)),
            random_state=Config.RANDOM_SEED
        )
        
        logger.info(f"Dataset splits:")
        logger.info(f"  - Training: {len(X_train)} samples")
        logger.info(f"  - Validation: {len(X_val)} samples")
        logger.info(f"  - Test: {len(X_test)} samples")
        
        # Train model
        logger.info("Starting model training...")
        history = model.train(
            X_train, y_train,
            X_val, y_val,
            epochs=Config.EPOCHS,
            batch_size=Config.BATCH_SIZE
        )
        
        # Evaluate on test set
        logger.info("Evaluating on test set...")
        metrics = model.evaluate(X_test, y_test)
        
        # Save model
        logger.info("Saving model...")
        model_path = model.save_model(Config.MODEL_DIR)
        
        # Print summary
        print("\n" + "="*60)
        print("Training Summary")
        print("="*60)
        print(f"Test Accuracy: {metrics['accuracy']:.2%}")
        print(f"Test AUC: {metrics['auc']:.4f}")
        print(f"Test Loss: {metrics['loss']:.4f}")
        print(f"Model saved to: {model_path}")
        print("="*60)
        
        logger.info("✅ Training complete!")
        
        return 0
        
    except FileNotFoundError as e:
        logger.error(f"Data files not found: {e}")
        logger.error("Please run 'python scripts/fetch_data.py' first!")
        return 1
        
    except Exception as e:
        logger.error(f"Error during training: {e}", exc_info=True)
        return 1


if __name__ == "__main__":
    sys.exit(main())