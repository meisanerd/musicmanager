#!/bin/bash
#############################################################################
# Default settings here
#############################################################################
SQLITE="sqlite3 -separator $'\t' -cmd 'PRAGMA foreign_keys = ON;' songs.db"
HTTPSERVER="python2 -m CGIHTTPServer 8000"
DEFAULT_EXTDIR="/mnt/usb"
#############################################################################

IFS=$'\n'

if [ ! -e songs.db ]; then
	echo "CREATE TABLE songlist (filename text primary key, artist text, title text, length decimal);" | eval $SQLITE
	echo "CREATE TABLE playlist (id integer primary key, filename varchar(255), build bool default 0, auto_create varchar(255) default \"\");" | eval $SQLITE
	echo "CREATE TABLE playlist_songs (playlist_id integer not null, song text not null, foreign key (playlist_id) references playlist (id), foreign key (song) references songlist (filename));" | eval $SQLITE
fi

main_menu () {
	echo "==================================================="
	echo "1: Sync Music"
	echo "2: Manage Playlists"
	echo "3: Manage Songs"
	echo "4: Start Playlist Management Web Server"
	echo "5: Generate Playlist Files"
	echo "6: Sync Playlist to Folder"
	echo "Q: Exit"
	while true; do
		read -p "Operation: " op
		case $op in
			[1] )
				clear
				sync_music
				break;;
			[2] )
				clear
				manage_playlists
				break;;
			[3] )
				clear
				manage_songs
				break;;
			[4] )
				clear
				cd webfiles
				eval $HTTPSERVER
				clear
				cd ..
				break;;
			[5] )
				clear
				generate_playlists
				break;;
			[6] )
				clear
				sync_playlist_to_file
				break;;
			[Qq] )
				exit
				break;;
		esac
	done
}

sync_music() {
	if [ -e "files.txt" ]; then
		echo "Error: files.txt already exists.  Either another sync is happening, or something broke.  Please manually delete this file before attempting to sync again."
		return
	fi
	for X in `echo "SELECT filename FROM songlist;" | eval $SQLITE`; do
		if [ ! -e "$X" ]; then
			echo "DELETE FROM playlist_songs WHERE song=\"$X\";" | eval $SQLITE
			echo "DELETE FROM songlist WHERE filename=\"$X\";" | eval $SQLITE
		fi
	done
	find . -name "*.flac" | sort > files.txt
	for X in `cat files.txt`; do
		LENGTH=`metaflac --show-total-samples --show-sample-rate "$X" | tr '\n' ' ' | awk '{print $1/$2}'`
		ARTIST=`metaflac --show-tag=ARTIST "$X"`
		ARTIST=${ARTIST:7}
		ARTIST=${ARTIST//\"/\\\"}
		TITLE=`metaflac --show-tag=TITLE "$X"`
		TITLE=${TITLE:6}
		TITLE=${TITLE//\"/\\\"}
		FILE=${X//\"/\\\"}
		echo "INSERT OR IGNORE INTO songlist VALUES (\"$FILE\",\"$ARTIST\",\"$TITLE\",\"$LENGTH\");" | eval $SQLITE
	done
	rm files.txt
	find . -name "*.mp3" | sort > files.txt
	for X in `cat files.txt`; do
		LENGTH=`ffmpeg -i "$X" 2>&1 | awk '/Duration/ {print substr($2,0,length($2)-1)}'`
		IFS=':' read -ra LENGTHARRAY <<< "$LENGTH"
		HRS=$((${LENGTHARRAY[0]} * 3600))
		MINS=$((${LENGTHARRAY[1]} * 60))
		LENGTH=`echo $HRS + $MINS + ${LENGTHARRAY[2]} | bc`
		ARTIST=`id3info "$X" | grep TPE1`
		ARTIST=${ARTIST:41}
		ARTIST=${ARTIST//\"/\\\"}
		TITLE=`id3info "$X" | grep TIT2`
		TITLE=${TITLE:47}
		TITLE=${TITLE//\"/\\\"}
		FILE=${X//\"/\\\"}
		echo "INSERT OR IGNORE INTO songlist VALUES (\"$FILE\",\"$ARTIST\",\"$TITLE\",\"$LENGTH\");" | eval $SQLITE
	done
	rm files.txt
	for X in `echo "SELECT rowid, auto_create FROM playlist WHERE auto_create IS NOT NULL AND auto_create != '';" | eval $SQLITE`; do
		IFS=$'\t' read -ra PLAYLIST <<< "$X"
		echo "DELETE FROM playlist_songs WHERE playlist_id=${PLAYLIST[0]};" | eval $SQLITE
		echo "INSERT INTO playlist_songs SELECT ${PLAYLIST[0]}, filename FROM songlist WHERE filename LIKE \"${PLAYLIST[1]}\";" | eval $SQLITE
	done
}

manage_playlists() {
	while true; do
		echo "==================================================="
		for X in `echo "SELECT rowid, filename, build, auto_create FROM playlist;" | eval $SQLITE`; do
			IFS=$'\t' read -ra PLAYLIST <<< "$X"
			PLS="${PLAYLIST[0]}: ${PLAYLIST[1]}"
			if [ "${PLAYLIST[2]}" -eq 1 ]; then
				PLS="$PLS (Build"
				if [ ${#PLAYLIST[3]} -gt 0 ]; then
					PLS="$PLS, Autocreate"
				fi
				PLS="$PLS)"
			else
				if [ ${#PLAYLIST[3]} -gt 0 ]; then
					PLS="$PLS (Autocreate)"
				fi
			fi
			echo "$PLS"
		done
		echo "N: New Playlist"
		echo "Q: Return to menu"
		read -p "Edit Playlist: " playlistid
		if [ "$playlistid" == "N" ] || [ "$playlistid" == "n" ]; then
			read -p "Playlist Filename: " newplaylist
			if [ ${#newplaylist} -gt 0 ]; then
				echo "INSERT INTO playlist (filename,build,auto_create) VALUES (\"$newplaylist\",0,\"\");" | eval $SQLITE
			fi
			continue;
		fi
		if [ "$playlistid" == "Q" ] || [ "$playlistid" == "q" ]; then
			clear
			return
		fi
		while true; do
			echo "==================================================="
			DATA=`echo "SELECT * FROM playlist WHERE rowid=$playlistid;" | eval $SQLITE`
			IFS=$'\t' read -ra PLAYLIST <<< "$DATA"
			echo "1 (Name): ${PLAYLIST[0]}"
			echo "2 (Build): ${PLAYLIST[1]}"
			echo "3 (Auto-create): ${PLAYLIST[2]}"
			echo "Q: Return to list"
			read -p "Operation: " op
			case $op in
				[1] )
					read -p "Playlist Filename: " newplaylist
					if [ ${#newplaylist} -gt 0 ]; then
						echo "UPDATE playlist SET filename=\"$newplaylist\" WHERE rowid=$playlistid;" | eval $SQLITE
					fi
					;;
				[2] )
					if [ ${PLAYLIST[1]} -eq 1 ]; then
						echo "UPDATE playlist SET build=0 WHERE rowid=$playlistid;" | eval $SQLITE
					else
						echo "UPDATE playlist SET build=1 WHERE rowid=$playlistid;" | eval $SQLITE
					fi
					;;
				[3] )
					read -p "Auto-create String (SQL Format): " autocreate
					echo "UPDATE playlist SET auto_create=\"$autocreate\" WHERE rowid=$playlistid;" | eval $SQLITE
					;;
				[Qq] )
					clear
					break;;
			esac
		done
	done;
}

manage_songs() {
	START=0
	WHERE=""
	filter=""
	while true; do
		echo "==================================================="
		for X in `echo "SELECT rowid, * FROM songlist $WHERE ORDER BY filename LIMIT $START, 20;" | eval $SQLITE`; do
			IFS=$'\t' read -ra SONG <<< "$X"
			echo "${SONG[0]}: ${SONG[3]} - ${SONG[2]}"
		done
		echo "N: Next Page"
		echo "P: Previous Page"
		if [ "${#filter}" -gt 0 ]; then
			echo "F: Filter ($filter)"
		else
			echo "F: Filter"
		fi
		echo "Q: Return to menu"
		read -p "Edit Song: " songid
		if [ "$songid" == "N" ] || [ "$songid" == "n" ]; then
			clear
			START=$(($START + 20))
			continue;
		fi
		if [ "$songid" == "P" ] || [ "$songid" == "p" ]; then
			clear
			START=$(($START - 20))
			continue;
		fi
		if [ "$songid" == "F" ] || [ "$songid" == "f" ]; then
			read -p "Filter String: " filter
			if [ "${#filter}" -gt 0 ]; then
				WHERE="WHERE filename LIKE \"%$filter%\""
			else
				WHERE=""
			fi
			START=0
			clear
			continue;
		fi
		if [ "$songid" == "Q" ] || [ "$songid" == "q" ]; then
			clear
			return
		fi
		clear
		while true; do
			echo "==================================================="
			DATA=`echo "SELECT * FROM songlist WHERE rowid=$songid;" | eval $SQLITE`
			IFS=$'\t' read -ra SONG <<< "$DATA"
			echo "Song: ${SONG[2]} - ${SONG[1]}"
			echo "File: ${SONG[0]}"
			for X in `echo "SELECT p.rowid, p.filename, LENGTH(p.auto_create), ps.song FROM playlist AS p LEFT JOIN playlist_songs AS ps ON p.rowid = ps.playlist_id AND ps.song = \"${SONG[0]}\";" | eval $SQLITE`; do
				IFS=$'\t' read -ra PLAYLIST <<< "$X"
				PLS="${PLAYLIST[0]}: ${PLAYLIST[1]}"
				if [ ${PLAYLIST[2]} -gt 0 ]; then
					PLS="$PLS (Auto,"
					if [ ${#PLAYLIST[3]} -gt 0 ]; then
						PLS="$PLS Yes)"
					else
						PLS="$PLS No)"
					fi
				else
					if [ ${#PLAYLIST[3]} -gt 0 ]; then
						PLS="$PLS (Yes)"
					else
						PLS="$PLS (No)"
					fi
				fi
				echo $PLS
			done
			echo "Q: Return to list"
			read -p "Operation: " op
			clear
			if [ "$op" == "Q" ] || [ "$op" == "q" ]; then
				break
			fi
			if [ `echo "SELECT COUNT(*) FROM playlist_songs WHERE song=\"${SONG[0]}\" AND playlist_id=$op;" | eval $SQLITE` -gt 0 ]; then
				echo "DELETE FROM playlist_songs WHERE song=\"${SONG[0]}\" AND playlist_id=$op;" | eval $SQLITE
			else
				echo "INSERT INTO playlist_songs (playlist_id, song) VALUES ($op, \"${SONG[0]}\");" | eval $SQLITE
			fi
		done
	done
}

generate_playlists() {
	for X in `echo "SELECT rowid, filename FROM playlist WHERE build=1;" | eval $SQLITE`; do
		IFS=$'\t' read -ra PLAYLIST <<< "$X"
		echo "[playlist]" > "${PLAYLIST[1]}"
		COUNT=0
		for Y in `echo "SELECT song FROM playlist_songs WHERE playlist_id=${PLAYLIST[0]} ORDER BY song ASC;" | eval $SQLITE`; do
			FILE=${Y//\"/\\\"}
			SONG=`echo "SELECT * FROM songlist WHERE filename=\"$FILE\";" | eval $SQLITE`
			IFS=$'\t' read -ra ITEM <<< "$SONG"
			COUNT=$((COUNT+1))
			echo "File$COUNT=${ITEM[0]}" >> "${PLAYLIST[1]}"
			echo "Title$COUNT=${ITEM[2]} - ${ITEM[1]}" >> "${PLAYLIST[1]}"
			echo "Length$COUNT=${ITEM[3]}" >> "${PLAYLIST[1]}"
		done
		echo "Version=2" >> "${PLAYLIST[1]}"
		sed -i "s/\[playlist\]/[playlist]\nNumberOfEntries=$COUNT/" "${PLAYLIST[1]}"
	done
	for X in `echo "SELECT filename FROM playlist WHERE build=0;" | eval $SQLITE`; do
		if [ -e "$X" ]; then
			rm "$X"
		fi
	done
}

sync_playlist_to_file() {
	DEST=$DEFAULT_EXTDIR
	while true; do
		echo "==================================================="
		for X in `echo "SELECT rowid, filename FROM playlist;" | eval $SQLITE`; do
			IFS=$'\t' read -ra PLAYLIST <<< "$X"
			echo "${PLAYLIST[0]}: ${PLAYLIST[1]}"
		done
		echo "Q: Return to menu"
		read -p "Playlist: " playlistid
		clear
		if [ "$playlistid" == "Q" ] || [ "$playlistid" == "q" ]; then
			return
		fi
		while true; do
			echo "==================================================="
			PLAYLIST=`echo "SELECT filename FROM playlist WHERE rowid=$playlistid;" | eval $SQLITE`
			echo "Sync $PLAYLIST to $DEST"
			echo "1: List Destination Files/Folders"
			echo "2: Change Directory"
			echo "3: List Files to be synced"
			echo "4: Sync Files"
			echo "Q: Back to menu"
			read -p "Operation: " op
			clear
			case $op in
				[1] )
					ls "$DEST"
					;;
				[2] )
					echo "Not implemented"
					;;
				[3] )
					if [ -e "rsync.txt" ]; then
						echo "Error: rsync.txt already exists.  Either someone else is performing a sync, or an error occurred.  Please manually remove this file before syncing again."
					else
						for X in `echo "SELECT song FROM playlist_songs WHERE playlist_id=$playlistid ORDER BY song ASC;" | eval $SQLITE`; do
							echo "$X" >> rsync.txt
						done
						find "$DEST" -type f | while read FILE; do
							NAME="$(echo "$FILE" | sed -e "s!^$DEST!!")"
							if ! grep -qF "$NAME" "rsync.txt"; then
								echo "Delete $FILE"
							fi
						done
						rsync -v --files-from=rsync.txt --dry-run . "$DEST"
						rm rsync.txt
					fi
					;;
				[4] )
					if [ -e "rsync.txt" ]; then
						echo "Error: rsync.txt already exists.  Either someone else is performing a sync, or an error occurred.  Please manually remove this file before syncing again."
					else
						for X in `echo "SELECT song FROM playlist_songs WHERE playlist_id=$playlistid ORDER BY song ASC;" | eval $SQLITE`; do
							echo "$X" >> rsync.txt
						done
						find "$DEST" -type f | while read FILE; do
							NAME="$(echo "$FILE" | sed -e "s!^$DEST!!")"
							if ! grep -qF "$NAME" "rsync.txt"; then
								rm "$FILE"
							fi
						done
						find "$DEST" -type d -empty -delete
						rsync -v --files-from=rsync.txt . "$DEST"
						rm rsync.txt
					fi
					;;
				[Qq] )
					clear
					break;;
			esac
		done
	done
}

while true; do
	main_menu
done
