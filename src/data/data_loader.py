"""
Data loading utilities
"""

import os
import json
import logging
from typing import Tuple, List, Dict
import numpy as np

logger = logging.getLogger(__name__)


class DataLoader:
    """Handles loading and preprocessing of match data"""
    
    def __init__(self, data_dir: str):
        """
        Initialize data loader
        
        Args:
            data_dir: Directory containing JSON data files
        """
        self.data_dir = data_dir
    
    def load_pro_matches(self) -> List[Dict]:
        """
        Load pro matches from JSON file
        
        Returns:
            List of match dictionaries
        """
        filepath = os.path.join(self.data_dir, 'pro_matches.json')
        
        if not os.path.exists(filepath):
            raise FileNotFoundError(
                f"Pro matches file not found: {filepath}\n"
                "Please run the data fetching script first!"
            )
        
        with open(filepath, 'r') as f:
            matches = json.load(f)
        
        logger.info(f"Loaded {len(matches)} pro matches from {filepath}")
        return matches
    
    def load_heroes(self) -> List[Dict]:
        """
        Load hero data from JSON file
        
        Returns:
            List of hero dictionaries
        """
        filepath = os.path.join(self.data_dir, 'heroes.json')
        
        if not os.path.exists(filepath):
            logger.warning(f"Heroes file not found: {filepath}")
            return []
        
        with open(filepath, 'r') as f:
            heroes = json.load(f)
        
        logger.info(f"Loaded {len(heroes)} heroes from {filepath}")
        return heroes
    
    def load_hero_stats(self) -> List[Dict]:
        """
        Load hero statistics from JSON file
        
        Returns:
            List of hero stat dictionaries
        """
        filepath = os.path.join(self.data_dir, 'hero_stats.json')
        
        if not os.path.exists(filepath):
            logger.warning(f"Hero stats file not found: {filepath}")
            return []
        
        with open(filepath, 'r') as f:
            stats = json.load(f)
        
        logger.info(f"Loaded stats for {len(stats)} heroes from {filepath}")
        return stats
    
    def get_latest_data_dir(self, base_dir: str = "./data") -> str:
        """
        Find the most recent data directory
        
        Args:
            base_dir: Base directory to search in
            
        Returns:
            Path to latest data directory
        """
        # Look for directories matching pattern opendota_YYYYMMDD_HHMMSS
        subdirs = [
            d for d in os.listdir(base_dir)
            if os.path.isdir(os.path.join(base_dir, d)) and d.startswith('opendota_')
        ]
        
        if not subdirs:
            raise FileNotFoundError(
                f"No data directories found in {base_dir}\n"
                "Please run fetch_opendota_data.py first!"
            )
        
        # Sort by timestamp (newest first)
        subdirs.sort(reverse=True)
        latest_dir = os.path.join(base_dir, subdirs[0])
        
        logger.info(f"Using latest data directory: {latest_dir}")
        return latest_dir