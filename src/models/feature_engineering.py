"""
Feature engineering for Dota 2 match prediction
"""

import numpy as np
from typing import Dict, List
import logging

logger = logging.getLogger(__name__)


class FeatureEngineer:
    """Handles feature extraction and engineering from match data"""
    
    def __init__(self, num_heroes: int = 130):
        """
        Initialize feature engineer
        
        Args:
            num_heroes: Number of heroes in Dota 2
        """
        self.num_heroes = num_heroes
        self.hero_id_map = {}
    
    def create_feature_vector(self, match: Dict) -> np.ndarray:
        """
        Create feature vector from match data
        
        Args:
            match: Match data dictionary
            
        Returns:
            Feature vector as numpy array
        """
        # Simple one-hot encoding for radiant and dire heroes
        # In production, you'd parse actual pick/ban data
        feature = np.zeros(self.num_heroes * 2)  # *2 for radiant and dire
        
        # This is a simplified example
        # You would extract actual hero picks from match data
        radiant_team = match.get('radiant_team_id', 0) % self.num_heroes
        dire_team = match.get('dire_team_id', 0) % self.num_heroes
        
        feature[radiant_team] = 1  # Radiant pick
        feature[self.num_heroes + dire_team] = 1  # Dire pick
        
        return feature
    
    def extract_features_and_labels(
        self,
        matches: List[Dict]
    ) -> tuple[np.ndarray, np.ndarray]:
        """
        Extract features and labels from match list
        
        Args:
            matches: List of match dictionaries
            
        Returns:
            Tuple of (features, labels) as numpy arrays
        """
        logger.info(f"Extracting features from {len(matches)} matches")
        
        features = []
        labels = []
        
        for match in matches:
            # Create feature vector
            feature = self.create_feature_vector(match)
            label = 1 if match.get('radiant_win', False) else 0
            
            features.append(feature)
            labels.append(label)
        
        X = np.array(features)
        y = np.array(labels)
        
        logger.info(f"Prepared {len(X)} training examples")
        logger.info(f"Feature shape: {X.shape}")
        logger.info(f"Radiant win rate: {np.mean(y):.2%}")
        
        return X, y
    
    def build_hero_mapping(self, heroes: List[Dict]) -> Dict[int, str]:
        """
        Build mapping from hero ID to hero name
        
        Args:
            heroes: List of hero data dictionaries
            
        Returns:
            Dictionary mapping hero ID to name
        """
        self.hero_id_map = {
            hero['id']: hero['localized_name']
            for hero in heroes
        }
        
        logger.info(f"Built hero mapping for {len(self.hero_id_map)} heroes")
        return self.hero_id_map