#!/usr/bin/env python3
"""
BillWatch Training Data Collector

Fetches bill data from Congress.gov API and formats for training:
- Bill text and official summaries
- Policy area classifications
"""

import os
import json
import argparse
import httpx
import asyncio
from pathlib import Path
from typing import List, Dict, Any


CONGRESS_API_BASE = "https://api.congress.gov/v3"


async def fetch_bills(api_key: str, congress: int = 118, limit: int = 100) -> List[Dict]:
    """Fetch bills from Congress.gov API."""
    bills = []
    offset = 0
    
    async with httpx.AsyncClient(timeout=30.0) as client:
        while len(bills) < limit:
            response = await client.get(
                f"{CONGRESS_API_BASE}/bill/{congress}",
                params={
                    "api_key": api_key,
                    "limit": min(50, limit - len(bills)),
                    "offset": offset,
                    "format": "json",
                }
            )
            
            if response.status_code != 200:
                print(f"Error fetching bills: {response.status_code}")
                break
            
            data = response.json()
            batch = data.get("bills", [])
            
            if not batch:
                break
            
            bills.extend(batch)
            offset += len(batch)
            
            print(f"Fetched {len(bills)} bills...")
    
    return bills


async def fetch_bill_details(api_key: str, bill: Dict) -> Dict[str, Any]:
    """Fetch detailed bill information including text and summary."""
    bill_type = bill.get("type", "").lower()
    bill_number = bill.get("number")
    congress = bill.get("congress")
    
    if not all([bill_type, bill_number, congress]):
        return None
    
    async with httpx.AsyncClient(timeout=30.0) as client:
        # Fetch bill details
        response = await client.get(
            f"{CONGRESS_API_BASE}/bill/{congress}/{bill_type}/{bill_number}",
            params={"api_key": api_key, "format": "json"}
        )
        
        if response.status_code != 200:
            return None
        
        details = response.json().get("bill", {})
        
        # Fetch summaries
        summary_response = await client.get(
            f"{CONGRESS_API_BASE}/bill/{congress}/{bill_type}/{bill_number}/summaries",
            params={"api_key": api_key, "format": "json"}
        )
        
        summaries = []
        if summary_response.status_code == 200:
            summaries = summary_response.json().get("summaries", [])
    
    # Extract relevant fields
    result = {
        "bill_id": f"{bill_type}{bill_number}-{congress}",
        "title": details.get("title", ""),
        "policy_area": details.get("policyArea", {}).get("name", "Unknown"),
        "introduced_date": details.get("introducedDate", ""),
        "latest_action": details.get("latestAction", {}).get("text", ""),
    }
    
    # Get the most detailed summary available
    if summaries:
        # Prefer "Introduced in House" or "Introduced in Senate" summaries
        for summary in summaries:
            if "Introduced" in summary.get("name", ""):
                result["official_summary"] = summary.get("text", "")
                break
        
        if "official_summary" not in result:
            result["official_summary"] = summaries[0].get("text", "")
    
    return result


def create_training_example(bill_details: Dict) -> Dict[str, str]:
    """Create a training example from bill details."""
    if not bill_details or not bill_details.get("official_summary"):
        return None
    
    # Create simplified summary from official summary
    # In production, you'd want human-written plain English summaries
    summary = bill_details["official_summary"]
    
    # Clean HTML tags from summary
    import re
    summary = re.sub(r'<[^>]+>', '', summary)
    summary = re.sub(r'\s+', ' ', summary).strip()
    
    return {
        "bill_id": bill_details["bill_id"],
        "title": bill_details["title"],
        "bill_text": summary[:2000],  # Use summary as proxy for full text
        "summary": summary[:500],  # Shorter version for training output
        "policy_area": bill_details["policy_area"],
    }


async def collect_data(api_key: str, congress: int, limit: int, output_dir: Path):
    """Main data collection function."""
    print(f"Fetching bills from Congress {congress}...")
    bills = await fetch_bills(api_key, congress, limit)
    
    print(f"Fetching details for {len(bills)} bills...")
    
    training_examples = []
    for i, bill in enumerate(bills):
        details = await fetch_bill_details(api_key, bill)
        
        if details:
            example = create_training_example(details)
            if example:
                training_examples.append(example)
        
        if (i + 1) % 10 == 0:
            print(f"Processed {i + 1}/{len(bills)} bills, {len(training_examples)} examples")
        
        # Rate limiting
        await asyncio.sleep(0.5)
    
    # Save to file
    output_file = output_dir / "bill_summaries_raw.jsonl"
    with open(output_file, 'w') as f:
        for example in training_examples:
            f.write(json.dumps(example) + '\n')
    
    print(f"\nSaved {len(training_examples)} training examples to {output_file}")
    print("\nNote: These use official summaries. For better training data,")
    print("have humans write plain English summaries.")


def main():
    parser = argparse.ArgumentParser(description="Collect BillWatch training data")
    parser.add_argument("--congress-api-key", required=True, help="Congress.gov API key")
    parser.add_argument("--congress", type=int, default=118, help="Congress number")
    parser.add_argument("--limit", type=int, default=100, help="Number of bills to fetch")
    parser.add_argument("--output", required=True, help="Output directory")
    
    args = parser.parse_args()
    output_dir = Path(args.output)
    output_dir.mkdir(parents=True, exist_ok=True)
    
    asyncio.run(collect_data(
        api_key=args.congress_api_key,
        congress=args.congress,
        limit=args.limit,
        output_dir=output_dir,
    ))


if __name__ == "__main__":
    main()
