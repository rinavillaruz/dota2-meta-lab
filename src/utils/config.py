"""
Configuration management
"""

import os
from typing import Optional


class Config:
    """Application configuration"""
    
    # Data settings
    DATA_DIR = os.getenv('DATA_DIR', './data/latest')
    OUTPUT_DIR = os.getenv('OUTPUT_DIR', './data')
    
    # Model settings
    MODEL_DIR = os.getenv('MODEL_DIR', './models')
    NUM_HEROES = int(os.getenv('NUM_HEROES', '130'))
    
    # Training settings
    EPOCHS = int(os.getenv('EPOCHS', '50'))
    BATCH_SIZE = int(os.getenv('BATCH_SIZE', '32'))
    VALIDATION_SPLIT = float(os.getenv('VALIDATION_SPLIT', '0.15'))
    TEST_SPLIT = float(os.getenv('TEST_SPLIT', '0.15'))
    RANDOM_SEED = int(os.getenv('RANDOM_SEED', '42'))
    
    # API settings
    OPENDOTA_API_KEY = os.getenv('OPENDOTA_API_KEY', None)
    API_RATE_LIMIT = float(os.getenv('API_RATE_LIMIT', '1.0'))  # requests per second
    
    # Logging
    LOG_LEVEL = os.getenv('LOG_LEVEL', 'INFO')
    LOG_DIR = os.getenv('LOG_DIR', './logs')
    
    @classmethod
    def get_data_dir(cls) -> str:
        """Get the data directory, creating if needed"""
        os.makedirs(cls.DATA_DIR, exist_ok=True)
        return cls.DATA_DIR
    
    @classmethod
    def get_model_dir(cls) -> str:
        """Get the model directory, creating if needed"""
        os.makedirs(cls.MODEL_DIR, exist_ok=True)
        return cls.MODEL_DIR
    
    @classmethod
    def get_log_dir(cls) -> str:
        """Get the log directory, creating if needed"""
        os.makedirs(cls.LOG_DIR, exist_ok=True)
        return cls.LOG_DIR
    
    @classmethod
    def validate(cls) -> bool:
        """
        Validate configuration
        
        Returns:
            True if configuration is valid
        """
        # Add validation logic here
        return True