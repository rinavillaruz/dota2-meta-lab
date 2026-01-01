"""
Store Dota 2 data in MongoDB
Usage: python scripts/store_database.py
"""
import json
import pandas as pd
from pymongo import MongoClient, ASCENDING, DESCENDING
from datetime import datetime
import os

class DatabaseManager:
    def __init__(self, connection_string='mongodb://localhost:27017/'):
        """Initialize MongoDB connection"""
        print(f"🔌 Connecting to MongoDB...")
        
        try:
            self.client = MongoClient(connection_string, serverSelectionTimeoutMS=5000)
            # Test connection
            self.client.server_info()
            
            self.db = self.client['dota2_meta_lab']
            print(f"✅ Connected to database: dota2_meta_lab")
            
        except Exception as e:
            print(f"❌ Could not connect to MongoDB: {e}")
            print(f"💡 Make sure MongoDB is running:")
            print(f"   - Install: brew install mongodb-community")
            print(f"   - Start: brew services start mongodb-community")
            raise
    
    def store_matches(self, matches_file='data/detailed_matches.json'):
        """Store match data in MongoDB"""
        print(f"\n📥 Loading matches from {matches_file}...")
        
        with open(matches_file, 'r') as f:
            matches = json.load(f)
        
        print(f"✅ Loaded {len(matches)} matches")
        
        print(f"💾 Storing matches in database...")
        
        collection = self.db['matches']
        
        # Add timestamp to each match
        for match in matches:
            match['stored_at'] = datetime.now()
            match['_id'] = match['match_id']  # Use match_id as MongoDB _id
        
        # Bulk insert (update if exists)
        from pymongo import ReplaceOne
        
        operations = [
            ReplaceOne(
                filter={'_id': match['_id']},
                replacement=match,
                upsert=True
            )
            for match in matches
        ]
        
        result = collection.bulk_write(operations)
        
        print(f"✅ Stored {result.upserted_count} new matches")
        print(f"✅ Updated {result.modified_count} existing matches")
        
        # Create indexes
        collection.create_index([('match_id', ASCENDING)], unique=True)
        collection.create_index([('stored_at', DESCENDING)])
        collection.create_index([('radiant_win', ASCENDING)])
        
        print(f"✅ Created indexes")
    
    def store_processed_data(self, processed_file='data/processed_matches.csv'):
        """Store processed features in MongoDB"""
        print(f"\n📥 Loading processed data from {processed_file}...")
        
        df = pd.read_csv(processed_file)
        print(f"✅ Loaded {len(df)} processed matches")
        
        print(f"💾 Storing processed features in database...")
        
        collection = self.db['processed_features']
        
        # Convert DataFrame to list of dicts
        records = df.to_dict('records')
        
        # Add timestamp
        for record in records:
            record['processed_at'] = datetime.now()
            record['_id'] = int(record['match_id'])  # Use match_id as _id
        
        # Bulk insert (update if exists)
        from pymongo import ReplaceOne
        
        operations = [
            ReplaceOne(
                filter={'_id': record['_id']},
                replacement=record,
                upsert=True
            )
            for record in records
        ]
        
        result = collection.bulk_write(operations)
        
        print(f"✅ Stored {result.upserted_count} new processed matches")
        print(f"✅ Updated {result.modified_count} existing processed matches")
        
        # Create indexes
        collection.create_index([('match_id', ASCENDING)], unique=True)
        collection.create_index([('radiant_win', ASCENDING)])
        
        print(f"✅ Created indexes")
    
    def store_model_metadata(self, metadata_file='models/metadata.json'):
        """Store model training metadata"""
        print(f"\n📥 Loading model metadata from {metadata_file}...")
        
        if not os.path.exists(metadata_file):
            print(f"⚠️  Metadata file not found, skipping...")
            return
        
        with open(metadata_file, 'r') as f:
            metadata = json.load(f)
        
        print(f"💾 Storing model metadata in database...")
        
        collection = self.db['model_metadata']
        
        # Add storage timestamp
        metadata['stored_at'] = datetime.now()
        
        # Insert as new document (track training history)
        result = collection.insert_one(metadata)
        
        print(f"✅ Stored model metadata with ID: {result.inserted_id}")
    
    def create_analytics_views(self):
        """Create useful analytics queries"""
        print(f"\n📊 Creating analytics views...")
        
        # Hero statistics
        hero_stats = self.db['matches'].aggregate([
            {'$unwind': '$players'},
            {'$group': {
                '_id': '$players.hero_id',
                'games': {'$sum': 1},
                'avg_kills': {'$avg': '$players.kills'},
                'avg_deaths': {'$avg': '$players.deaths'},
                'avg_assists': {'$avg': '$players.assists'},
            }},
            {'$sort': {'games': -1}},
            {'$limit': 20}
        ])
        
        print(f"🏆 Top 20 Most Played Heroes:")
        for i, hero in enumerate(hero_stats, 1):
            print(f"   {i}. Hero {hero['_id']}: {hero['games']} games, "
                  f"{hero['avg_kills']:.1f} K / {hero['avg_deaths']:.1f} D / {hero['avg_assists']:.1f} A")
    
    def get_database_stats(self):
        """Get database statistics"""
        print(f"\n📈 Database Statistics:")
        
        matches_count = self.db['matches'].count_documents({})
        processed_count = self.db['processed_features'].count_documents({})
        models_count = self.db['model_metadata'].count_documents({})
        
        print(f"   Matches: {matches_count}")
        print(f"   Processed features: {processed_count}")
        print(f"   Model versions: {models_count}")
        
        # Latest model
        if models_count > 0:
            latest_model = self.db['model_metadata'].find_one(
                sort=[('trained_at', DESCENDING)]
            )
            print(f"   Latest model trained: {latest_model['trained_at']}")
            print(f"   Training data size: {latest_model['num_matches']} matches")
    
    def close(self):
        """Close database connection"""
        self.client.close()
        print(f"\n🔌 Database connection closed")

def main():
    print("=" * 60)
    print("💾 DOTA2 Meta Lab - Database Storage")
    print("=" * 60)
    
    try:
        # Initialize database manager
        db = DatabaseManager()
        
        # Store raw match data
        if os.path.exists('data/detailed_matches.json'):
            db.store_matches('data/detailed_matches.json')
        else:
            print(f"\n⚠️  No match data found, skipping...")
        
        # Store processed features
        if os.path.exists('data/processed_matches.csv'):
            db.store_processed_data('data/processed_matches.csv')
        else:
            print(f"\n⚠️  No processed data found, skipping...")
        
        # Store model metadata
        if os.path.exists('models/metadata.json'):
            db.store_model_metadata('models/metadata.json')
        else:
            print(f"\n⚠️  No model metadata found, skipping...")
        
        # Show analytics
        db.create_analytics_views()
        
        # Show stats
        db.get_database_stats()
        
        # Close connection
        db.close()
        
        print("\n" + "=" * 60)
        print("✅ Database storage complete!")
        print("=" * 60)
        print("\n💡 You can now query the database:")
        print("   mongo")
        print("   use dota2_meta_lab")
        print("   db.matches.find().pretty()")
        
    except Exception as e:
        print(f"\n❌ Error: {e}")
        print(f"\n💡 MongoDB Setup:")
        print(f"   1. Install: brew install mongodb-community")
        print(f"   2. Start: brew services start mongodb-community")
        print(f"   3. Verify: mongo --version")

if __name__ == "__main__":
    main()