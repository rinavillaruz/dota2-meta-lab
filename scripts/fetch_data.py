"""
Fetch Dota 2 match data from OpenDota API
Usage: python scripts/fetch_data.py
"""
import requests
import json
import os
import time
from datetime import datetime

class OpenDotaFetcher:
    BASE_URL = "https://api.opendota.com/api"
    
    def __init__(self):
        self.session = requests.Session()
        self.session.headers.update({
            'User-Agent': 'Dota2MetaLab/1.0'
        })
    
    def fetch_public_matches(self, limit=100):
        """Fetch recent public matches (basic info only)"""
        print(f"📥 Fetching {limit} recent public matches...")
        
        url = f"{self.BASE_URL}/publicMatches"
        response = self.session.get(url)
        response.raise_for_status()
        
        matches = response.json()
        print(f"✅ Fetched {len(matches)} public matches")
        
        return matches[:limit]
    
    def fetch_match_details(self, match_id):
        """Fetch detailed information about a specific match"""
        url = f"{self.BASE_URL}/matches/{match_id}"
        
        try:
            response = self.session.get(url)
            response.raise_for_status()
            return response.json()
        except requests.exceptions.HTTPError as e:
            if e.response.status_code == 429:
                print("⚠️  Rate limited! Waiting 60 seconds...")
                time.sleep(60)
                return self.fetch_match_details(match_id)
            elif e.response.status_code == 404:
                print(f"⚠️  Match {match_id} not found")
                return None
            raise
    
    def fetch_pro_matches(self, limit=100):
        """Fetch recent professional matches"""
        print(f"📥 Fetching {limit} pro matches...")
        
        url = f"{self.BASE_URL}/proMatches"
        response = self.session.get(url)
        response.raise_for_status()
        
        matches = response.json()
        print(f"✅ Fetched {len(matches)} pro matches")
        
        return matches[:limit]
    
    def save_to_file(self, data, filename):
        """Save data to JSON file"""
        os.makedirs(os.path.dirname(filename) if os.path.dirname(filename) else '.', exist_ok=True)
        
        with open(filename, 'w') as f:
            json.dump(data, f, indent=2)
        
        print(f"💾 Saved {len(data)} items to {filename}")

def main():
    print("=" * 60)
    print("🎮 DOTA2 Meta Lab - Data Fetcher")
    print("=" * 60)
    print()
    
    fetcher = OpenDotaFetcher()
    
    # Create data directory
    os.makedirs('data', exist_ok=True)
    
    # Fetch public matches (these are quick, just basic info)
    public_matches = fetcher.fetch_public_matches(limit=100)
    fetcher.save_to_file(public_matches, 'data/public_matches.json')
    
    print()
    
    # Fetch detailed info for matches (this is slow, has all the data we need)
    print("📥 Fetching detailed match data (this may take a while)...")
    detailed_matches = []
    
    # Only fetch details for first 50 matches (to be nice to the API)
    for i, match in enumerate(public_matches[:50], 1):
        match_id = match['match_id']
        print(f"  [{i}/50] Match {match_id}...", end=' ')
        
        try:
            details = fetcher.fetch_match_details(match_id)
            if details:
                detailed_matches.append(details)
                print("✅")
            else:
                print("⏭️  Skipped")
            
            # Be nice to the API - wait 1 second between requests
            time.sleep(1)
        except Exception as e:
            print(f"❌ Error: {e}")
            continue
    
    fetcher.save_to_file(detailed_matches, 'data/detailed_matches.json')
    
    print()
    
    # Fetch pro matches for high-quality training data
    pro_matches = fetcher.fetch_pro_matches(limit=100)
    fetcher.save_to_file(pro_matches, 'data/pro_matches.json')
    
    print()
    print("=" * 60)
    print("✅ Data fetching complete!")
    print(f"   - {len(public_matches)} public matches (basic info)")
    print(f"   - {len(detailed_matches)} detailed matches (full data)")
    print(f"   - {len(pro_matches)} pro matches")
    print("=" * 60)
    print()
    print("Next step: python scripts/analyze_data.py")

if __name__ == "__main__":
    main()