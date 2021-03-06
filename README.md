# musicmanager
This script allows command-line management of a directory of music files in either FLAC or MP3 format.
It recursively scans child directories for music files and adds them to a database where you can then assign them to playlists.

Playlists can either have songs manually added to them, or you can automatically add them via basic SQL queries.

Playlists can then be exported as a .pls file, or be synced to an external storage device.

## Requirements
### For the script
sqlite3
### For FLAC processing
flac (metaflac command)
### For MP3 Processing
ffmpeg
id3info
### For the playlist management web interface
python (tested with 2.7, other versions might work with tweaks)
