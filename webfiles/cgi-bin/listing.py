#!/usr/bin/env python2.7
import subprocess
import sys
import ConfigParser
import urllib
import cgi

config=ConfigParser.SafeConfigParser()
config.read("settings.ini")

args = cgi.FieldStorage()
if "page" not in args:
	page = 1
else:
	page = int(args["page"].value)

start = (page - 1) * 20

print "Content-Type: text/html"
print

sys.stdout.flush()
try:
	query=subprocess.check_output("echo \"SELECT * FROM songlist ORDER BY filename ASC LIMIT " + str(start) + ", 20;\" | " + config.get("commands","sqlitecmd"), shell=True)
	songs=query.split("\n")
	query=subprocess.check_output("echo \"SELECT rowid, filename FROM playlist WHERE auto_create=\\\"\\\" ORDER BY filename ASC;\" | " + config.get("commands","sqlitecmd"), shell=True)
	playlists=[]
	for line in query.split("\n"):
		playlists.append(line.split("\t"))
except subprocess.CalledProcessError, e:
	print e.output

sys.stdout.flush()
print "<HTML><BODY><TABLE style='width: 100%'>"
print "<TR><TH>Song</TH>"
for playlist in playlists:
	if playlist[0]:
		print "<TH>" + playlist[1] + "</TH>"
print "</TH></TR>"
for song in songs:
	if song:
		songdata=song.split("\t")
		print "<TR><TD>"
		print songdata[2] + " - " + songdata[1]
		print "<BR />"
		print songdata[0]
		for playlist in playlists:
			if playlist[0]:
				params = { 'playlist' : playlist[0], 'song' : songdata[0] }
				print "</TD><TD><IFRAME SRC='/cgi-bin/playlist_song.py?" + urllib.urlencode(params) + "' width='30' height='30' scrolling='no'></IFRAME>"
		print "</TD></TR>"
print "</TABLE>"
if page > 1:
	print "<A HREF='/cgi-bin/listing.py?page=" + str(page - 1) + "'>Back</A>"
print "<A HREF='/cgi-bin/listing.py?page=" + str(page + 1) + "'>Next</A>"
print "</BODY></HTML>"
