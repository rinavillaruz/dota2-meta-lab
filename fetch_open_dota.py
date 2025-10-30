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

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
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


def main():
    """Main function to fetch and save Dota 2 data"""
    
    # Get API key from environment variable (optional)
    api_key = os.getenv('OPENDOTA_API_KEY')
    
    # Initialize fetcher
    fetcher = OpenDotaFetcher(api_key=api_key)
    
    # Create output directory
    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
    output_dir = f"./data/opendota_{timestamp}"
    os.makedirs(output_dir, exist_ok=True)
    
    logger.info(f"Saving data to {output_dir}")
    
    # Fetch heroes data
    heroes = fetcher.get_heroes()
    fetcher.save_data(heroes, 'heroes.json', output_dir)
    
    # Fetch hero statistics
    hero_stats = fetcher.get_hero_stats()
    fetcher.save_data(hero_stats, 'hero_stats.json', output_dir)
    
    # Fetch pro matches
    pro_matches = fetcher.get_pro_matches(limit=100)
    fetcher.save_data(pro_matches, 'pro_matches.json', output_dir)
    
    # Fetch high MMR public matches
    logger.info("Fetching high MMR matches...")
    high_mmr_matches = fetcher.get_public_matches(mmr_bracket=7, limit=50)
    fetcher.save_data(high_mmr_matches, 'high_mmr_matches.json', output_dir)
    
    # Optionally fetch detailed match data (slower)
    if len(pro_matches) > 0:
        logger.info("Fetching detailed match data for first 5 pro matches...")
        detailed_matches = []
        for match in pro_matches[:5]:
            match_id = match['match_id']
            details = fetcher.get_match_details(match_id)
            if details:
                detailed_matches.append(details)
        
        fetcher.save_data(detailed_matches, 'detailed_matches.json', output_dir)
    
    logger.info("✅ Data fetching complete!")
    logger.info(f"📁 Data saved to: {output_dir}")
    
    # Print summary
    print("\n" + "="*50)
    print("Data Fetching Summary")
    print("="*50)
    print(f"Heroes: {len(heroes)}")
    print(f"Hero Stats: {len(hero_stats)}")
    print(f"Pro Matches: {len(pro_matches)}")
    print(f"High MMR Matches: {len(high_mmr_matches)}")
    print(f"Output Directory: {output_dir}")
    print("="*50)


if __name__ == "__main__":
    main()