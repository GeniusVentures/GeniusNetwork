import os
import sys
import tarfile
import zipfile
import re
import json
import aiohttp
import asyncio
from aiohttp import ClientSession
from concurrent.futures import ThreadPoolExecutor
from tqdm import tqdm

# Function to get all releases information
async def get_all_releases(session: ClientSession, owner, repo, headers):
    url = f"https://api.github.com/repos/{owner}/{repo}/releases"
    async with session.get(url, headers=headers) as response:
        response.raise_for_status()
        return await response.json()

# Function to download a file with progress bar
async def download_file(session: ClientSession, url, local_filename, headers, rate_limit_factor):
    async with session.get(url, headers=headers) as response:
        response.raise_for_status()
        total_size = int(response.headers.get('content-length', 0))
        with open(local_filename, 'wb') as f, tqdm(
                total=total_size, unit='B', unit_scale=True, desc=local_filename, ascii=True
        ) as progress_bar:
            while True:
                chunk = await response.content.read(8192)
                if not chunk:
                    break
                f.write(chunk)
                progress_bar.update(len(chunk))
        await asyncio.sleep(1 / rate_limit_factor)  # Apply rate limiting

# Function to extract tar or zip files with progress bar
def extract_file(file_path, extract_to, skip_first_directory=False):
    if file_path.endswith('.tar.gz') or file_path.endswith('.tgz'):
        with tarfile.open(file_path, 'r:gz') as tar:
            members = tar.getmembers()
            if skip_first_directory:
                members = [m for m in members if '/' in m.name]
                for member in members:
                    member.name = '/'.join(member.name.split('/')[1:])
            total_size = sum(m.size for m in members)
            with tqdm(total=total_size, unit='B', unit_scale=True, desc=file_path, ascii=True) as progress_bar:
                for member in members:
                    tar.extract(member, path=extract_to)
                    progress_bar.update(member.size)
    elif file_path.endswith('.zip'):
        with zipfile.ZipFile(file_path, 'r') as zip_ref:
            members = zip_ref.infolist()
            if skip_first_directory:
                members = [m for m in members if '/' in m.filename]
                for member in members:
                    member.filename = '/'.join(member.filename.split('/')[1:])
            total_size = sum(m.file_size for m in members)
            with tqdm(total=total_size, unit='B', unit_scale=True, desc=file_path, ascii=True) as progress_bar:
                for member in members:
                    if member.filename:  # Ensure filename is not empty
                        zip_ref.extract(member, path=extract_to)
                        progress_bar.update(member.file_size)
    else:
        raise ValueError("Unsupported file type")

# Example functions to be called on regex match
def loadlib(file_path):
    print(f"Loaded library and extracted: {file_path}")

def loadsrc(file_path):
    print(f"Loaded source files and extracted: {file_path}")

# Function to read regex patterns and associated functions from a file
def read_config(config_file):
    regex_patterns = []
    owner, repo, release_regex, branch, branch_target_dir = None, None, None, None, None
    with open(config_file, 'r') as file:
        for line in file:
            line = line.strip()
            if line and not line.startswith('#'):
                parts = line.split(',')
                if parts[0] == 'OWNER':
                    owner = parts[1]
                elif parts[0] == 'REPO':
                    repo = parts[1]
                elif parts[0] == 'RELEASE_REGEX':
                    release_regex = parts[1]
                elif parts[0] == 'BRANCH':
                    branch = parts[1]
                    branch_target_dir = parts[2]
                else:
                    pattern, target_dir, func_name = parts
                    try:
                        func = globals()[func_name]
                    except KeyError:
                        print(f"Warning: Function '{func_name}' is not defined.")
                        func = None
                    regex_patterns.append((pattern, target_dir, func))
    return owner, repo, release_regex, regex_patterns, branch, branch_target_dir

# Function to read the lock file
def read_lock_file(lock_file):
    if os.path.exists(lock_file):
        with open(lock_file, 'r') as f:
            return json.load(f)
    return {"downloaded": [], "branch": None}

# Function to update the lock file
def update_lock_file(lock_file, data):
    with open(lock_file, 'w') as f:
        json.dump(data, f, indent=4)

# Function to check if a file has already been downloaded
def is_already_downloaded(lock_data, url):
    for entry in lock_data["downloaded"]:
        if entry["url"] == url:
            return True
    return False

# Function to organize files into directories based on regex and call functions
def organize_files(file_path, regex_patterns, release_path_parts):
    for pattern, target_dir, func in regex_patterns:
        if re.match(pattern, os.path.basename(file_path)):
            final_target_dir = target_dir.format(*release_path_parts)
            os.makedirs(final_target_dir, exist_ok=True)
            new_path = os.path.join(final_target_dir, os.path.basename(file_path))
            os.rename(file_path, new_path)
            if func:
                func(new_path)
            break

async def process_asset(session, download_dir, asset, release_path_parts, regex_patterns, lock_data, lock_file, testrun, semaphore, headers, rate_limit_factor, remove_downloaded):
    async with semaphore:
        file_name = asset['name']
        download_url = asset['browser_download_url']

        # Check if the file matches the regex patterns before downloading
        if not any(re.match(pattern, file_name) for pattern, _, _ in regex_patterns):
            return

        if is_already_downloaded(lock_data, download_url):
            print(f"Skipping already downloaded file: {file_name}")
            return

        if testrun:
            for pattern, target_dir, func in regex_patterns:
                if re.match(pattern, file_name):
                    final_target_dir = target_dir.format(*release_path_parts)
                    print(f"Test run: would download {file_name} and extract to '{final_target_dir}'")
            return

        # Determine the specific download directory based on the release part
        specific_download_dir = os.path.join(download_dir, release_path_parts[0])
        os.makedirs(specific_download_dir, exist_ok=True)
        file_path = os.path.join(specific_download_dir, file_name)

        # Download the asset
        await download_file(session, download_url, file_path, headers, rate_limit_factor)

        # Extract the downloaded file to its final destination
        for pattern, target_dir, func in regex_patterns:
            if re.match(pattern, file_name):
                final_target_dir = target_dir.format(*release_path_parts)
                os.makedirs(final_target_dir, exist_ok=True)
                loop = asyncio.get_running_loop()
                with ThreadPoolExecutor() as pool:
                    await loop.run_in_executor(pool, extract_file, file_path, final_target_dir)
                if func:
                    func(os.path.join(final_target_dir, file_name))
                # Update lock file after successful download and extraction
                lock_data["downloaded"].append({"version": release_path_parts, "url": download_url})
                update_lock_file(lock_file, lock_data)
                break

        # Clean up if specified
        if remove_downloaded:
            os.remove(file_path)

async def download_branch(session, owner, repo, branch, branch_target_dir, download_dir, headers, rate_limit_factor, testrun, lock_data, lock_file):
    branch_url = f"https://github.com/{owner}/{repo}/archive/refs/heads/{branch}.zip"
    branch_filename = f"{branch}.zip"
    branch_download_path = os.path.join(download_dir, branch_filename)
    branch_extract_path = branch_target_dir.format(branch, "branch")

    if testrun:
        print(f"Test run: would download branch {branch} and extract to '{branch_extract_path}'")
        return

    # Check if branch has already been downloaded
    if lock_data.get("branch") == branch_url:
        print(f"Branch {branch} is already downloaded.")
        return

    os.makedirs(download_dir, exist_ok=True)
    await download_file(session, branch_url, branch_download_path, headers, rate_limit_factor)

    os.makedirs(branch_extract_path, exist_ok=True)
    loop = asyncio.get_running_loop()
    with ThreadPoolExecutor() as pool:
        await loop.run_in_executor(pool, extract_file, branch_download_path, branch_extract_path, True)

    # Update lock file after successful download and extraction
    lock_data["branch"] = branch_url
    update_lock_file(lock_file, lock_data)

async def main(config_file, download_dir='downloads', testrun=False, max_concurrent_downloads=None, rate_limit_factor=1, remove_downloaded=False):
    # Read config
    owner, repo, release_regex, regex_patterns, branch, branch_target_dir = read_config(config_file)
    if not owner or not repo or not release_regex:
        print("Error: OWNER, REPO, and RELEASE_REGEX must be specified in the config file.")
        return

    # Determine the path of the lock file
    config_dir = os.path.dirname(os.path.abspath(config_file))
    lock_file = os.path.join(config_dir, 'config.lock')

    # Read lock file
    lock_data = read_lock_file(lock_file)

    # Determine the max number of concurrent downloads
    if max_concurrent_downloads is None:
        max_concurrent_downloads = os.cpu_count() or 4

    semaphore = asyncio.Semaphore(max_concurrent_downloads)

    # Use GitHub token if available
    github_token = os.getenv('GITHUB_TOKEN')
    headers = {'Authorization': f'token {github_token}'} if github_token else {}

    async with aiohttp.ClientSession() as session:
        # Get all releases information
        releases_info = await get_all_releases(session, owner, repo, headers)

        # Process each release
        tasks = []
        for release_info in releases_info:
            release_name = release_info['name']
            match = re.match(release_regex, release_name)
            if not match:
                continue  # Ignore non-matching releases

            release_path_parts = match.groups()

            # Process each asset in the release asynchronously
            for asset in release_info['assets']:
                task = process_asset(session, download_dir, asset, release_path_parts, regex_patterns, lock_data, lock_file, testrun, semaphore, headers, rate_limit_factor, remove_downloaded)
                tasks.append(task)

        # Download and extract the specified branch if provided
        if branch and branch_target_dir:
            await download_branch(session, owner, repo, branch, branch_target_dir, download_dir, headers, rate_limit_factor, testrun, lock_data, lock_file)

        await asyncio.gather(*tasks)

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python script.py <config_file> [<download_dir>] [--testrun] [--max-concurrent-downloads=<num>] [--rate-limit-factor=<num>] [--remove-downloaded]")
    else:
        config_file = sys.argv[1]
        download_dir = sys.argv[2] if len(sys.argv) > 2 and not sys.argv[2].startswith('--') else 'downloads'
        testrun = '--testrun' in sys.argv
        max_concurrent_downloads = None
        rate_limit_factor = 1
        remove_downloaded = '--remove-downloaded' in sys.argv
        for arg in sys.argv:
            if arg.startswith('--max-concurrent-downloads='):
                max_concurrent_downloads = int(arg.split('=')[1])
            elif arg.startswith('--rate-limit-factor='):
                rate_limit_factor = int(arg.split('=')[1])
        asyncio.run(main(config_file, download_dir, testrun, max_concurrent_downloads, rate_limit_factor, remove_downloaded))
