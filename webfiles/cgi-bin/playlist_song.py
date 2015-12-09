#!/usr/bin/env python2.7
import subprocess
import sys
import cgi
import ConfigParser
import urllib

config=ConfigParser.SafeConfigParser()
config.read("settings.ini")
print "Content-Type: text/html"
print

args = cgi.FieldStorage()

sys.stdout.flush()
try:
	query = "echo \"SELECT COUNT(*) FROM playlist_songs WHERE playlist_id=" + args["playlist"].value + " AND song=\\\"" + args["song"].value + "\\\";\" | " + config.get("commands","sqlitecmd")
	resp=subprocess.check_output(query, shell=True)
except subprocess.CalledProcessError, e:
	print e.output

sys.stdout.flush()
print "<HTML><HEAD><STYLE>html, body { margin: 0; padding: 0; }</STYLE></HEAD><BODY>"
params = { 'playlist' : args["playlist"].value, 'song' : args["song"].value, 'toggle' : 'yes' }
print "<FORM ACTION='/cgi-bin/playlist_song.py?" + urllib.urlencode(params) + "' METHOD='get'>"
if int(resp) > 0:
	print "<BUTTON TYPE='submit' STYLE='background-color: #00FF00; width: 30px; height: 30px;'></BUTTON>"
else:
	print "<BUTTON TYPE='submit' STYLE='background-color: #FF0000; width: 30px; height: 30px;'></BUTTON>"
print "</FORM></BODY></HTML>"
