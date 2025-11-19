#!/usr/bin/env python3
"""
OpenDota Data Fetcher
Fetches Dota 2 match data from OpenDota API for meta analysis
"""

import os
import json
import time
import requests
from datetime import datetime
from typing import List, Dict, Optional
import logging

logger = logging.getLogger(__name__)


class OpenDotaFetcher:
    """Fetches data from OpenDota API"""
    
    BASE_URL = "https://api.opendota.com/api"
    
    def __init__(self, api_key: Optional[str] = None):
        """
        Initialize OpenDota fetcher
        
        Args:
            api_key: Optional API key for higher rate limits
        """
        self.api_key = api_key
        self.session = requests.Session()
        if api_key:
            self.session.headers.update({'Authorization': f'Bearer {api_key}'})
    
    def _make_request(self, endpoint: str, params: Optional[Dict] = None) -> Dict:
        """
        Make API request with rate limiting
        
        Args:
            endpoint: API endpoint
            params: Query parameters
            
        Returns:
            JSON response as dictionary
        """
        url = f"{self.BASE_URL}/{endpoint}"
        
        try:
            response = self.session.get(url, params=params, timeout=30)
            response.raise_for_status()
            
            # Respect rate limits
            time.sleep(1)  # 1 request per second
            
            return response.json()
        
        except requests.exceptions.RequestException as e:
            logger.error(f"Error fetching {endpoint}: {e}")
            return {}
    
    def get_pro_matches(self, limit: int = 100) -> List[Dict]:
        """
        Fetch recent pro matches
        
        Args:
            limit: Number of matches to fetch
            
        Returns:
            List of match data
        """
        logger.info(f"Fetching {limit} pro matches...")
        
        matches = []
        less_than_match_id = None
        
        while len(matches) < limit:
            params = {}
            if less_than_match_id:
                params['less_than_match_id'] = less_than_match_id
            
            batch = self._make_request('proMatches', params=params)
            
            if not batch:
                break
            
            matches.extend(batch)
            less_than_match_id = batch[-1]['match_id']
            
            logger.info(f"Fetched {len(matches)} matches so far...")
            
            if len(batch) < 100:  # No more matches available
                break
        
        return matches[:limit]
    
    def get_match_details(self, match_id: int) -> Dict:
        """
        Get detailed information about a specific match
        
        Args:
            match_id: Match ID
            
        Returns:
            Match details
        """
        logger.info(f"Fetching match details for {match_id}")
        return self._make_request(f'matches/{match_id}')
    
    def get_heroes(self) -> List[Dict]:
        """
        Get list of all heroes
        
        Returns:
            List of hero data
        """
        logger.info("Fetching hero data...")
        return self._make_request('heroes')
    
    def get_hero_stats(self) -> List[Dict]:
        """
        Get hero statistics (pick rate, win rate, etc.)
        
        Returns:
            List of hero statistics
        """
        logger.info("Fetching hero statistics...")
        return self._make_request('heroStats')
    
    def get_public_matches(self, mmr_bracket: Optional[int] = None, limit: int = 100) -> List[Dict]:
        """
        Fetch public matches
        
        Args:
            mmr_bracket: MMR bracket filter (0-7, higher = better players)
            limit: Number of matches to fetch
            
        Returns:
            List of match data
        """
        logger.info(f"Fetching {limit} public matches (MMR bracket: {mmr_bracket})...")
        
        params = {}
        if mmr_bracket is not None:
            params['mmr_bracket'] = mmr_bracket
        
        matches = []
        less_than_match_id = None
        
        while len(matches) < limit:
            if less_than_match_id:
                params['less_than_match_id'] = less_than_match_id
            
            batch = self._make_request('publicMatches', params=params)
            
            if not batch:
                break
            
            matches.extend(batch)
            less_than_match_id = batch[-1]['match_id']
            
            logger.info(f"Fetched {len(matches)} matches so far...")
        
        return matches[:limit]
    
    def save_data(self, data: any, filename: str, output_dir: str = "./data"):
        """
        Save data to JSON file
        
        Args:
            data: Data to save
            filename: Output filename
            output_dir: Output directory
        """
        os.makedirs(output_dir, exist_ok=True)
        filepath = os.path.join(output_dir, filename)
        
        with open(filepath, 'w') as f:
            json.dump(data, f, indent=2)
        
        logger.info(f"Saved data to {filepath}")