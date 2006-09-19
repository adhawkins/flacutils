#!/usr/bin/perl -w

use MP3::Tag;

sub FixName
{
	my $Name=shift;
	
	$Name=~s/\//\-/g;
	$Name=~s/\:/\-/g;
	$Name=~s/"/\-/g;
	$Name=~s/'/\-/g;
	$Name=~s/`/\-/g;
	$Name=~s/;/\-/g;
	$Name=~s/\?/\-/g;
	
	return "$Name";
}

sub TrackFileName
{
	my $TrackNum=shift;
	my $TrackTitle=shift;
	
	$TrackTitle=FixName($TrackTitle);
	
	return sprintf("%02d - %s.mp3",$TrackNum,$TrackTitle);
}

sub ProcessSingleTrackFlac
{
	foreach $File (@_)
	{
		open METAFLAC,"metaflac --list --block-type=VORBIS_COMMENT \"$File\" |";
		
		my $Album="";
		my $Artist="";
		my $TrackTitle="";
		my $TrackNumber=0;
		my $Year="";
		
		while (<METAFLAC>)
		{
			$Year=$1 if /DATE=(\d*)$/;
			
			$Year=$1 if /YEAR=(\d*)$/;
			
			$Album=$1 if /ALBUM=(.*)$/;
			
			$Artist=$1 if /ARTIST=(.*)$/;
			
			$TrackTitle=$1 if /TITLE=(.*)$/;
			
			$TrackNumber=$1 if /TRACKNUMBER=(.*)$/;
		}
		
		close METAFLAC;
		
		my $AlbumFile=FixName($Album);
		
		my $TrackFile=TrackFileName($TrackNumber,$TrackTitle);
		if (-f "$DestDir/$Artist/$AlbumFile/$TrackFile")
		{
			#print "File $DestDir/$Artist/$AlbumFile/$TrackFile already exists\n";
		}
		else
		{
			if (!-d $DestDir)
			{
				print "Making $DestDir\n";
				mkdir ("$DestDir/");
			}
			
			if (!-d "$DestDir/$Artist")
			{
				print "Making $DestDir/$Artist\n";
				mkdir ("$DestDir/$Artist");
			}
			
			if (!-d "$DestDir/$Artist/$AlbumFile")
			{
				print "Making $DestDir/$Artist/$AlbumFile\n";
				mkdir ("$DestDir/$Artist/$AlbumFile");
			}
			
			my $RetVal=system "flac -d -c \"$File\" | lame --quiet --preset fast standard - \"$DestDir/$Artist/$AlbumFile/tmp.mp3\"";
			if ($RetVal==0)
			{
				my $NewFile=sprintf("$DestDir/$Artist/$AlbumFile/%s",TrackFileName($TrackNumber,$TrackTitle));
				
				unlink $NewFile;
				rename "$DestDir/$Artist/$AlbumFile/tmp.mp3",$NewFile;
				
				my $mp3=MP3::Tag->new($NewFile);
				$mp3->get_tags;
				
				$mp3->new_tag("ID3v1");
				
				$id3=$mp3->{ID3v1};
				
				$id3->song($TrackTitle);
				$id3->album($Album);
				$id3->artist($Artist);
				$id3->track($TrackNumber);
				
				if ($Year)
				{
					$id3->year($Year);
				}
				
				$id3->write_tag();
				$mp3->close();
			}
		}
	}
}

sub ProcessMultiTrackFlac
{
	foreach $File (@_)
	{
		open METAFLAC,"metaflac --list --block-type=VORBIS_COMMENT \"$File\" |";
		
		my $Album="";
		my $Artist="";
		my $Year="";
		my $Genre="";
		my @TrackArtist;
		my @TrackTitle;
		my @TrackNumber;
		my $DiskNumber;
		
		while (<METAFLAC>)
		{
			$Year=$1 if /DATE=(\d*)$/;
			
			$Year=$1 if /YEAR=(\d*)$/;
			
			$Album=$1 if /ALBUM=(.*)$/;
			
			$Artist=$1 if /ARTIST=(.*)$/;
			
			$Genre=$1 if /GENRE=(.*)$/;
			
			$DiskNumber=$1 if /DISCNUMBER=(.*)$/;
			
			$TrackArtist[$1]=$2 if /ARTIST\[(\d*)\]=(.*)$/;
			
			$TrackTitle[$1]=$2 if /TITLE\[(\d*)\]=(.*)$/;
			
			$TrackNumber[$1]=$2 if /TRACKNUMBER\[(\d*)\]=(.*)$/;
		}
		
		close METAFLAC;
		
		if ($Artist eq "")
		{
			$Artist="Various Artists";
		}
		
		my $AlbumFile=FixName($Album);

		my $TrackFile=TrackFileName($TrackNumber[$#TrackNumber],$TrackTitle[$#TrackNumber]);
		if ($DiskNumber)
		{
			$TrackFile=sprintf("%d - %s",$DiskNumber,$TrackFile);
		}

		if (-f "$DestDir/$Artist/$AlbumFile/$TrackFile")
		{
			#print "File $DestDir/$Artist/$AlbumFile/$TrackFile already exists\n";
		}
		else
		{
			if (!-d $DestDir)
			{
				mkdir ("$DestDir/");
			}
			
			if (!-d "$DestDir/$Artist")
			{
				mkdir ("$DestDir/$Artist");
			}
			
			if (!-d "$DestDir/$Artist/$AlbumFile")
			{
				mkdir ("$DestDir/$Artist/$AlbumFile");
			}

			system "metaflac --export-cuesheet-to=\"$Flac.cue\" \"$Flac\"";
			my $RetVal=system "cuebreakpoints \"$Flac.cue\" | shntool split -n \"\" -d \"$DestDir/$Artist/$AlbumFile/\" -o cust ext=mp3 \{ lame --quiet --preset fast standard - %f \} \"$Flac\"";
			unlink "$Flac.cue";
			
			if ($RetVal==0)
			{
				for (my $count=0;$count<$#TrackNumber+1;$count++)
				{
					my $Number=$TrackNumber[$count];
					
					if ($TrackTitle[$count])
					{
						my $ThisTitle=$TrackTitle[$count];
						my $TrackFile=TrackFileName($Number,$ThisTitle);
						
						if ($DiskNumber)
						{
							$TrackFile=sprintf("%d - %s",$DiskNumber,$TrackFile);
						}
						
						my $OldFile=sprintf("$DestDir/$Artist/$AlbumFile/%03d.mp3",$count);
						my $NewFile=sprintf("$DestDir/$Artist/$AlbumFile/%s",$TrackFile);

						unlink $NewFile;
						rename $OldFile,$NewFile;
						
						my $mp3=MP3::Tag->new($NewFile);
						$mp3->get_tags;
						
						my $id3=$mp3->new_tag("ID3v2");
						
						$id3->add_frame("TIT2",$ThisTitle);
						$id3->add_frame("TALB",$Album);
						$id3->add_frame("TRCK",$Number);
						
						if ($TrackArtist[$count])
						{
							$id3->add_frame("TPE1",$TrackArtist[$count]);
							$id3->add_frame("TCMP","1");
						}
						else
						{
							$id3->add_frame("TPE1",$Artist);
						}
						
						if ($Year)
						{
							$id3->add_frame("TYER",$Year);
						}

						if ($Genre)
						{
							$id3->add_frame("TCON",$Genre);
						}

						if ($DiskNumber)
						{
							$id3->add_frame("TPOS",$DiskNumber);
						}
						$id3->write_tag();
						$mp3->close();
					}
				}
				
				unlink  "\"$Flac.cue\"";
			}
		}
	}
}

sub ScanFlacs
{
	my @Dirs;
	
	foreach my $SourceDir (@_)
	{
		opendir FLACDIR,$SourceDir;
		while (my $DirEntry=readdir(FLACDIR))
		{
			if (($DirEntry ne ".") && ($DirEntry ne "..") && -d "$SourceDir/$DirEntry")
			{
				$Dirs[$#Dirs + 1]="$SourceDir/$DirEntry";
			}
			
			$Flacs[$#Flacs + 1]="$SourceDir/$DirEntry" if $DirEntry=~/\.flac$/;
		}
	}
	
	foreach my $Dir (@Dirs)
	{
		ScanFlacs($Dir);
	}
}

sub SingleTrackFlac
{
	my $Flac=shift;
	
	$RetVal=system("metaflac --export-cuesheet-to=- \"$Flac\" 2>/dev/null >/dev/null");
	if ($RetVal==0)
	{
		return 0;
	}
	else
	{
		return 1;
	}
}

sub ProcessFlac
{
	foreach my $Flac (@_)
	{
		if (SingleTrackFlac($Flac))
		{
			ProcessSingleTrackFlac($Flac);
		}
		else
		{
			ProcessMultiTrackFlac($Flac);
		}
	}
}

@Flacs=();

ScanFlacs($ARGV[0]);
$DestDir=$ARGV[1];

foreach $Flac (@Flacs)
{
	ProcessFlac($Flac);
}
