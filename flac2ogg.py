#!/usr/bin/python

import sys
import os
import mutagen.flac
import mutagen.oggvorbis
import re
import shutil
import filecmp

def ExtractCoverArt(FlacFile,MP3Dir):
	CoverArt=os.path.join(os.path.dirname(FlacFile),"cover.jpg")
	print "Cover art is " + CoverArt

	DestFile=os.path.join(MP3Dir,"Cover.jpg")
	
	if os.path.exists(CoverArt):
		if os.path.ctime(CoverArt) > os.path.ctime(DestFile):
			print "Copying cover art file"
			shutil.copyfile(CoverArt,DestFile)
		else:
			print "Cover art hasn't changed"
	else:
		TmpFile=os.path.join(os.path.dirname(FlacFile),"tmpcover.jpg")
		
		print "Extracting cover art from FLAC to " + TmpFile
		os.system("metaflac --export-picture-to=\"" + TmpFile + "\" \"" + FlacFile + "\"")
		
		if os.path.exists(TmpFile):
			if not os.path.exists(DestFile) or not filecmp.cmp(TmpFile,DestFile):
				print "Copying extracted cover art file"
				shutil.copyfile(TmpFile,DestFile)
			else:
				print "Extracted cover art matches the one already there"
				
			os.unlink(TmpFile)					
		else:
			print TmpFile + " doesn't exist after extraction"

def ProcessSingleTrackFlac(basedir,file,destdir):
	FullPath=os.path.join(basedir,file)
		
	MaxTrack=0
	GlobalTags={}
			
	FlacMetadata=mutagen.flac.Open(FullPath)

	for key in FlacMetadata.keys():
		if key!= "coverart" and key != "vendor":
			if not key.startswith("replaygain"):
				GlobalTags[key]=FlacMetadata[key];

	MP3Dir=os.path.join(destdir,os.path.dirname(file))
	(dummy,MP3Base)=os.path.split(file)
	(MP3Base,dummy)=os.path.splitext(MP3Base)

	TrackFile=os.path.join(MP3Dir,MP3Base)+".ogg"

	if not os.path.exists(TrackFile):
		if not os.path.exists(os.path.dirname(TrackFile)):
			os.makedirs(os.path.dirname(TrackFile))

		print "Extracting " + FullPath
		os.system("flac -s -d -c \"" + FullPath + "\" | oggenc -Q -q 5 -o \"" + TrackFile + "\" - ");

	if os.path.exists(TrackFile):
		ActualFileTags = LoadOggFileTags(TrackFile)
		
		if GlobalTags != ActualFileTags:
			print "Tagging " + TrackFile
			WriteOggTags(TrackFile,GlobalTags)
	else:
		print "Whoops - " + TrackFile + "doesn't exist"

	ExtractCoverArt(FullPath,MP3Dir)

def ProcessMultiTrackFlac(basedir,file,destdir):
	FullPath=os.path.join(basedir,file)
		
	MaxTrack=0
	GlobalTags={}
	TrackTags={}
	
	FlacMetadata=mutagen.flac.Open(FullPath)
		
	for key in FlacMetadata.keys():
		if key!="coverart" and key!="vendor":
			if not key.startswith("replaygain"):
				match=re.search("(.*)\[(.*)\]",key)
				if match!=None:
					if int(match.group(2))>MaxTrack:
						MaxTrack=int(match.group(2));

					if TrackTags.get(int(match.group(2)),-1)==-1:
						TrackTags[int(match.group(2))]=dict()
									
					TrackTags[int(match.group(2))][match.group(1)]=FlacMetadata[key];
				else:
					GlobalTags[key]=FlacMetadata[key]

	MP3Dir=os.path.join(destdir,os.path.dirname(file))
	(dummy,MP3Base)=os.path.split(file)
	(MP3Base,dummy)=os.path.splitext(MP3Base)

	TrackFile=os.path.join(MP3Dir,MP3Base)
	TrackFile+=" - %02d" %MaxTrack + ".ogg"

	if not os.path.exists(TrackFile):
		if not os.path.exists(os.path.dirname(TrackFile)):
			os.makedirs(os.path.dirname(TrackFile))
			
		print "Extracting " + FullPath
		os.system("metaflac --export-cuesheet-to=\"" + FullPath + ".cue\" \"" + FullPath + "\"")
		RetVal=os.system("cuebreakpoints \"" + FullPath + ".cue\" 2>/dev/null | shntool split -O always -t \"\" -n \"%02d\" -d \"" + MP3Dir + "\" -o 'cust ext=ogg oggenc -q 5 -o %f - '  \"" + FullPath + "\"")
		os.unlink(FullPath+".cue")
		
		if RetVal==0:
			for Number in range(MaxTrack):
				OldFile=os.path.join(MP3Dir,"%02d" %(Number+1)) + ".ogg"
				NewFile=os.path.join(MP3Dir,MP3Base) + " - %02d" %(Number+1) + ".ogg";
				
				if os.path.exists(NewFile):
					os.unlink(NewFile)
					
				os.rename(OldFile,NewFile)
				
	GlobalTagKeys=GlobalTags.keys()

	for Number in range(MaxTrack):
		TrackFile=os.path.join(MP3Dir,MP3Base)
		TrackFile+=" - %02d" %(Number+1)+ ".ogg"
		
		RequiredFileTags=dict()
		
		TrackTagKeys=TrackTags[Number+1].keys()
		
		for Key in TrackTagKeys:
			RequiredFileTags[Key]=TrackTags[Number+1][Key]

		for Key in GlobalTagKeys:
			if Key not in TrackTags[Number+1]:
				RequiredFileTags[Key]=GlobalTags[Key]
			
		ActualFileTags = LoadOggFileTags(TrackFile)
		
		if RequiredFileTags != ActualFileTags:
			print "Tagging " + TrackFile
			WriteOggTags(TrackFile,RequiredFileTags)

	ExtractCoverArt(FullPath,MP3Dir)

def WriteOggTags(file,tags):
	metadata = mutagen.oggvorbis.Open(file)
	metadata.delete()
	
	keys = tags.keys()
	for key in keys:
		metadata[key]=tags[key]
		
	metadata.save()
	
def LoadOggFileTags(file):
	ret = dict()
	metadata = mutagen.oggvorbis.Open(file)
	for key in metadata.keys():
		if not key.startswith("replaygain"):
			ret[key]=metadata[key]
	
	return ret

def SingleTrackFlac(file):
	ret=os.system("metaflac --export-cuesheet-to=- \"" + file + "\" 2>/dev/null >/dev/null")
	if (ret==0):
		return False
	else:
		return True

def ProcessFlac(basedir,file,destdir):
	fullpath=os.path.join(basedir,file)
	if SingleTrackFlac(fullpath):
		ProcessSingleTrackFlac(basedir,file,destdir)
	else:
		ProcessMultiTrackFlac(basedir,file,destdir)
		
def GetFlacFiles(basedir, extradir="", files=None):
	if files==None:
		retfiles=[]
	else:
		retfiles=files
		
	thisdir=os.path.join(basedir,extradir)
	
	entries=os.listdir(thisdir)
	
	for entry in entries:
		if os.path.isdir(os.path.join(thisdir,entry)):
			GetFlacFiles(basedir,os.path.join(extradir,entry),retfiles)
		else:
			(root,ext)=os.path.splitext(entry)
			
			if (ext==".flac"):
				retfiles.append(os.path.join(extradir,entry))
		
	return retfiles
	
if len(sys.argv)==3:
	srcdir=sys.argv[1]
	destdir=sys.argv[2]
	
	files=GetFlacFiles(srcdir)

	Count=1
	for file in files:
		print str(Count) + " of " + str(len(files)) + " - " + file
		Count=Count+1
		
		ProcessFlac(srcdir,file,destdir)
else:
	print "Usage: " + sys.argv[0] + " srcdir destdir"
