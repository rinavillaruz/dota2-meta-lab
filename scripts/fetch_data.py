#!/usr/bin/env python3
"""
Fetch Dota 2 match data from OpenDota API
Usage: python scripts/fetch_data.py
"""

import sys
from pathlib import Path

# Add project root to path
project_root = Path(__file__).parent.parent
sys.path.insert(0, str(project_root))

from datetime import datetime
from src.data import OpenDotaFetcher
from src.utils import Config, setup_logging

logger = setup_logging(level=Config.LOG_LEVEL)


def main():
    """Main function to fetch and save Dota 2 data"""
    
    logger.info("🎮 Starting Dota 2 Data Fetcher")
    
    # Initialize fetcher
    fetcher = OpenDotaFetcher(api_key=Config.OPENDOTA_API_KEY)
    
    # Create output directory with timestamp
    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
    output_dir = f"{Config.OUTPUT_DIR}/opendota_{timestamp}"
    
    logger.info(f"Saving data to {output_dir}")
    
    try:
        # Fetch heroes data
        logger.info("Fetching heroes...")
        heroes = fetcher.get_heroes()
        fetcher.save_data(heroes, 'heroes.json', output_dir)
        
        # Fetch hero statistics
        logger.info("Fetching hero statistics...")
        hero_stats = fetcher.get_hero_stats()
        fetcher.save_data(hero_stats, 'hero_stats.json', output_dir)
        
        # Fetch pro matches
        logger.info("Fetching pro matches...")
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
        print(f"\n💡 To use this data for training, update DATA_DIR in .env:")
        print(f"   DATA_DIR={output_dir}")
        
    except Exception as e:
        logger.error(f"Error during data fetching: {e}", exc_info=True)
        sys.exit(1)


if __name__ == "__main__":
    main()