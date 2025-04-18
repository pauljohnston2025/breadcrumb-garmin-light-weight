#!/usr/bin/env python3

import requests
import json
from urllib.parse import urljoin

BASE_URL = "https://server.arcgisonline.com/arcgis/rest/services/"
REQUEST_TIMEOUT = 20 # seconds

def get_json_response(url):
    """Fetches JSON response from a URL, handling potential errors."""
    # Ensure URL requests JSON format
    if "?f=json" not in url.lower():
        url += "?f=json"

    print(f"Requesting URL: {url}")
    try:
        response = requests.get(url, timeout=REQUEST_TIMEOUT)
        response.raise_for_status()  # Raise HTTPError for bad responses (4xx or 5xx)
        return response.json()
    except requests.exceptions.Timeout:
        print(f"Timeout error fetching {url}")
    except requests.exceptions.HTTPError as e:
        print(f"HTTP error fetching {url}: {e}")
    except requests.exceptions.RequestException as e:
        print(f"Request error fetching {url}: {e}")
    except json.JSONDecodeError as e:
        print(f"Error decoding JSON from {url}: {e}")
    except Exception as e:
        print(f"Unexpected error processing {url}: {e}")
    return None

def scrape_service_details(service_url):
    """
    Scrapes details for a single MapServer service if it's tiled.

    Args:
        service_url (str): The full URL to the MapServer endpoint.

    Returns:
        dict: A dictionary containing name, min/max zoom, and url if tiled,
              otherwise None.
    """
    data = get_json_response(service_url)
    if not data:
        return None

    # Check if it's a tiled service (MapServer with cache)
    is_tiled = data.get('singleFusedMapCache', False) and 'tileInfo' in data

    if is_tiled:
        try:
            # Extract Name (usually the segment before /MapServer or /ImageServer)
            # Handle potential trailing slash in input URL before splitting
            name_parts = service_url.rstrip('/').split('/')
            service_type = name_parts[-1] # Should be MapServer or ImageServer etc.
            service_name = name_parts[-2] if len(name_parts) >= 2 else "Unknown"

            # Extract LODs (Levels of Detail) from tileInfo
            lods = data.get('tileInfo', {}).get('lods', [])
            if not lods:
                print(f"Tiled service {service_url} has no LODs defined.")
                min_zoom = None
                max_zoom = None
            else:
                # Assuming 'level' directly corresponds to zoom level
                levels = [lod.get('level') for lod in lods if lod.get('level') is not None]
                if not levels:
                     print(f"LODs found but no 'level' key for: {service_url}")
                     min_zoom = None
                     max_zoom = None
                else:
                    min_zoom = min(levels)
                    max_zoom = max(levels)

            return {
                "name": service_name,
                "tilelayermin": min_zoom,
                "tilelayermax": max_zoom,
                "url": service_url # The MapServer URL itself
            }
        except KeyError as e:
            print(f"Missing expected key {e} when parsing details for {service_url}")
        except Exception as e:
            print(f"Error parsing details for {service_url}: {e}")
            return None # Don't let one service failure stop everything

    # print(f"Service not tiled or missing tileInfo: {service_url}")
    return None # Not a tiled service we're interested in

def process_url(current_url, results_list):
    """
    Recursively processes URLs (base, folders) to find and scrape MapServer services.

    Args:
        current_url (str): The URL to process (base or folder).
        results_list (list): The list to append found tile server details to.
    """
    print(f"Processing directory: {current_url}")
    dir_data = get_json_response(current_url)
    if not dir_data:
        return # Stop processing this branch if directory fetch failed

    # --- Process Services in the current directory ---
    for service in dir_data.get('services', []):
        service_name = service.get('name')
        service_type = service.get('type')

        # We are primarily interested in MapServer for typical web tiles
        # ImageServer can also be tiled, but let's stick to MapServer for now per initial request.
        if service_name and service_type == 'MapServer':
            # Construct the full service URL relative to the base
            # The 'name' can contain folder paths (e.g., "Elevation/World_Hillshade")
            # urljoin handles combining the base and the potentially nested name correctly
            full_service_url = urljoin(BASE_URL, f"{service_name}/{service_type}")

            print(f"Checking service: {full_service_url}")
            service_details = scrape_service_details(full_service_url)
            if service_details:
                print(f"Found tiled service: {service_details['name']}")
                results_list.append(service_details)
        # else:
            # print(f"Skipping service '{service_name}' (Type: {service_type})")


    # --- Process Folders recursively ---
    for folder in dir_data.get('folders', []):
        # Construct the full folder URL relative to the base
        folder_url = urljoin(BASE_URL, f"{folder}/") # Ensure trailing slash for urljoin
        process_url(folder_url, results_list) # Recursive call


# --- Main Execution ---
if __name__ == "__main__":
    all_tile_servers = []
    print(f"Starting scrape process from: {BASE_URL}")

    try:
        process_url(BASE_URL, all_tile_servers)
    except Exception as e:
        print(f"An unexpected critical error occurred during scraping: {e}", exc_info=True)


    print(f"Scraping finished. Found {len(all_tile_servers)} potential tile servers.")
    print("\n" + "="*40)
    print("       ArcGIS Online Tile Servers")
    print("="*40)

    if all_tile_servers:
        # Sort results alphabetically by name for consistent output
        all_tile_servers.sort(key=lambda x: x['name'])
        for server in all_tile_servers:
            # format wanted https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}
            # format found 'https://server.arcgisonline.com/arcgis/rest/services/Reference/World_Transportation/MapServer'
            url = server['url'] + '/tile/{z}/{y}/{x}'
            name = server['name'].replace('_', " ")
            print(f"new TileServerInfo(\"{url}\", {server['tilelayermin']}, {server['tilelayermax']}), // Esri - {name}")
    else:
        print("No tile servers (MapServer with singleFusedMapCache=true) were found.")

    print("="*40)