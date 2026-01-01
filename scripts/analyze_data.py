"""
Analyze Dota 2 match data and prepare for ML training
Usage: python scripts/analyze_data.py
"""
import json
import pandas as pd
import numpy as np
from collections import Counter
import matplotlib.pyplot as plt
import os

class MatchAnalyzer:
    def __init__(self, data_file='data/detailed_matches.json'):
        """Initialize analyzer with match data"""
        print(f"📊 Loading data from {data_file}...")
        
        with open(data_file, 'r') as f:
            self.matches = json.load(f)
        
        print(f"✅ Loaded {len(self.matches)} matches")
    
    def extract_features(self):
        """Extract features for ML training"""
        print("\n🔧 Extracting features from matches...")
        
        features_list = []
        
        for match in self.matches:
            try:
                # Basic match info
                match_id = match.get('match_id')
                radiant_win = 1 if match.get('radiant_win') else 0
                duration = match.get('duration', 0)
                
                # Extract hero picks for each team
                radiant_heroes = []
                dire_heroes = []
                
                for player in match.get('players', []):
                    hero_id = player.get('hero_id')
                    
                    # Radiant team is player_slot < 128
                    if player.get('player_slot', 0) < 128:
                        radiant_heroes.append(hero_id)
                    else:
                        dire_heroes.append(hero_id)
                
                # Only include matches with full teams (5v5)
                if len(radiant_heroes) != 5 or len(dire_heroes) != 5:
                    continue
                
                # Team statistics
                radiant_kills = sum(p.get('kills', 0) for p in match.get('players', []) if p.get('player_slot', 0) < 128)
                dire_kills = sum(p.get('kills', 0) for p in match.get('players', []) if p.get('player_slot', 0) >= 128)
                
                radiant_gold = sum(p.get('total_gold', 0) for p in match.get('players', []) if p.get('player_slot', 0) < 128)
                dire_gold = sum(p.get('total_gold', 0) for p in match.get('players', []) if p.get('player_slot', 0) >= 128)
                
                radiant_xp = sum(p.get('total_xp', 0) for p in match.get('players', []) if p.get('player_slot', 0) < 128)
                dire_xp = sum(p.get('total_xp', 0) for p in match.get('players', []) if p.get('player_slot', 0) >= 128)
                
                features = {
                    'match_id': match_id,
                    'radiant_win': radiant_win,
                    'duration': duration,
                    'radiant_hero_1': radiant_heroes[0],
                    'radiant_hero_2': radiant_heroes[1],
                    'radiant_hero_3': radiant_heroes[2],
                    'radiant_hero_4': radiant_heroes[3],
                    'radiant_hero_5': radiant_heroes[4],
                    'dire_hero_1': dire_heroes[0],
                    'dire_hero_2': dire_heroes[1],
                    'dire_hero_3': dire_heroes[2],
                    'dire_hero_4': dire_heroes[3],
                    'dire_hero_5': dire_heroes[4],
                    'radiant_kills': radiant_kills,
                    'dire_kills': dire_kills,
                    'radiant_gold': radiant_gold,
                    'dire_gold': dire_gold,
                    'radiant_xp': radiant_xp,
                    'dire_xp': dire_xp,
                }
                
                features_list.append(features)
                
            except Exception as e:
                print(f"⚠️  Error processing match: {e}")
                continue
        
        df = pd.DataFrame(features_list)
        print(f"✅ Extracted features from {len(df)} matches")
        
        return df
    
    def analyze_hero_stats(self, df):
        """Analyze hero pick rates and win rates"""
        print("\n📈 Analyzing hero statistics...")
        
        # Get all hero picks
        all_heroes = []
        for col in df.columns:
            if 'hero' in col:
                all_heroes.extend(df[col].tolist())
        
        # Count picks
        hero_picks = Counter(all_heroes)
        
        # Calculate win rates for each hero (as radiant)
        hero_wins = {}
        hero_games = {}
        
        for _, row in df.iterrows():
            radiant_heroes = [row[f'radiant_hero_{i}'] for i in range(1, 6)]
            dire_heroes = [row[f'dire_hero_{i}'] for i in range(1, 6)]
            
            radiant_won = row['radiant_win'] == 1
            
            for hero in radiant_heroes:
                hero_games[hero] = hero_games.get(hero, 0) + 1
                if radiant_won:
                    hero_wins[hero] = hero_wins.get(hero, 0) + 1
            
            for hero in dire_heroes:
                hero_games[hero] = hero_games.get(hero, 0) + 1
                if not radiant_won:
                    hero_wins[hero] = hero_wins.get(hero, 0) + 1
        
        # Calculate win rates
        hero_win_rates = {
            hero: (hero_wins.get(hero, 0) / games * 100) 
            for hero, games in hero_games.items() if games >= 5  # At least 5 games
        }
        
        print(f"\n🏆 Top 10 Most Picked Heroes:")
        for hero, count in hero_picks.most_common(10):
            win_rate = hero_win_rates.get(hero, 0)
            print(f"   Hero {hero}: {count} picks, {win_rate:.1f}% win rate")
        
        print(f"\n⭐ Top 10 Highest Win Rate Heroes (min 5 games):")
        sorted_win_rates = sorted(hero_win_rates.items(), key=lambda x: x[1], reverse=True)[:10]
        for hero, win_rate in sorted_win_rates:
            games = hero_games[hero]
            print(f"   Hero {hero}: {win_rate:.1f}% win rate ({games} games)")
        
        return hero_picks, hero_win_rates
    
    def analyze_match_duration(self, df):
        """Analyze match duration patterns"""
        print("\n⏱️  Analyzing match duration...")
        
        avg_duration = df['duration'].mean()
        median_duration = df['duration'].median()
        
        print(f"   Average duration: {avg_duration/60:.1f} minutes")
        print(f"   Median duration: {median_duration/60:.1f} minutes")
        
        # Win rate by duration
        short_games = df[df['duration'] < 1800]  # Less than 30 min
        long_games = df[df['duration'] >= 1800]
        
        print(f"   Short games (<30 min): {len(short_games)} matches, {short_games['radiant_win'].mean()*100:.1f}% radiant win")
        print(f"   Long games (>=30 min): {len(long_games)} matches, {long_games['radiant_win'].mean()*100:.1f}% radiant win")
    
    def save_processed_data(self, df, filename='data/processed_matches.csv'):
        """Save processed data for ML training"""
        print(f"\n💾 Saving processed data to {filename}...")
        
        os.makedirs(os.path.dirname(filename) if os.path.dirname(filename) else '.', exist_ok=True)
        df.to_csv(filename, index=False)
        
        print(f"✅ Saved {len(df)} processed matches")
        print(f"   Features: {list(df.columns)}")

def main():
    print("=" * 60)
    print("📊 DOTA2 Meta Lab - Data Analyzer")
    print("=" * 60)
    
    # Initialize analyzer
    analyzer = MatchAnalyzer('data/detailed_matches.json')
    
    # Extract features
    df = analyzer.extract_features()
    
    if len(df) == 0:
        print("\n❌ No valid matches found! Run fetch_data.py first.")
        return
    
    # Analyze data
    analyzer.analyze_hero_stats(df)
    analyzer.analyze_match_duration(df)
    
    # Save processed data
    analyzer.save_processed_data(df)
    
    print("\n" + "=" * 60)
    print("✅ Data analysis complete!")
    print("=" * 60)
    print("\nNext step: python scripts/train_model.py")

if __name__ == "__main__":
    main()