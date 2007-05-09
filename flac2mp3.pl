#!/usr/bin/perl -w

use MP3::Tag;

sub MakeDirTree
{
	my $Directory=shift;
	
	my @Dirs=split(/\//,$Directory);
	
	my $Dir="";
	for $ThisDir (@Dirs)
	{
		$Dir.=$ThisDir."/";
		mkdir($Dir);
	}
}
	
sub ParseFile
{
	
	my $File=shift;
	my $BasePath=shift;

	$BasePath=~s/\+/\\\+/;
	$BasePath=~s/\$/\\\$/;
	$BasePath=~s/\^/\\\^/;
	$BasePath=~s/\!/\\\!/;

	if ($File =~ /${BasePath}\/(.*)\/(.*).flac/)
	{
		return ($1,$2);
	}
	else 
	{
		if ($File =~ /${BasePath}\/(.*).flac/)
		{
			return ($BasePath,$1);
		}
	}
}

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
		($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,
			$atime,$FlacMTime,$ctime,$blksize,$blocks)
				= stat($File);
		
		open METAFLAC,"metaflac --list --block-type=VORBIS_COMMENT \"$File\" |";
		
		my $Album="";
		my $Artist="";
		my $ArtistSort="";
		my $TrackTitle="";
		my $TrackNumber=0;
		my $Year="";
		my $Genre="";
		my $DiskNumber;
		my $Created=0;
		
		while (<METAFLAC>)
		{
			$Year=$1 if /DATE=(\d*)$/;
			
			$Year=$1 if /YEAR=(\d*)$/;
			
			$Album=$1 if /ALBUM=(.*)$/;
			
			$Artist=$1 if /ARTIST=(.*)$/;
			
			$ArtistSort=$1 if /ARTISTSORT=(.*)$/;
			
			$TrackTitle=$1 if /TITLE=(.*)$/;
			
			$TrackNumber=$1 if /TRACKNUMBER=(.*)$/;

			$DiskNumber=$1 if /DISCNUMBER=(.*)$/;
			
			$Genre=$1 if /GENRE=(.*)$/;
		}
		
		close METAFLAC;
		
		($MP3Dir,$MP3Base)=ParseFile($File,$SourceDir);
		$MP3Dir=$DestDir."/".$MP3Dir;

		my $TrackFile="$MP3Dir/$MP3Base.mp3";
		
		if (-f "$TrackFile")
		{
			#print "File $TrackFile already exists\n";
		}
		else
		{
			$Created=1;
			print "File $TrackFile doesn't exist\n";
			
			if (!-d $MP3Dir)
			{
				MakeDirTree ($MP3Dir);
			}
			
			my $RetVal=system "flac -d -c \"$File\" | lame --quiet --preset fast standard - \"$TrackFile\"";
		}
		
		if (-f "$TrackFile")
		{
			($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,
				$atime,$MP3MTime,$ctime,$blksize,$blocks)
					= stat($TrackFile);
			
			
			if ($MP3MTime<$FlacMTime || $Created==1)
			{
				print "Tagging $TrackFile\n";
						
				my $mp3=MP3::Tag->new($TrackFile);
				$mp3->get_tags;
				
	      if (exists $mp3->{ID3v1}) 
	      {
					$mp3->{ID3v1}->remove_tag;
		    }
		    
				my $id3=$mp3->new_tag("ID3v2");
				
				$id3->add_frame("TIT2",$TrackTitle);
				$id3->add_frame("TALB",$Album);
				$id3->add_frame("TPE1",$Artist);
				
				if ($ArtistSort)
				{
					$id3->add_frame("TSOP",$ArtistSort);
				}
					
				$id3->add_frame("TRCK",$TrackNumber);
				
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
		else
		{
			print "Whoops - $TrackFile doesn't exist\n";
		}
	}
}

sub ProcessMultiTrackFlac
{
	foreach $File (@_)
	{
		($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,
			$atime,$FlacMTime,$ctime,$blksize,$blocks)
				= stat($File);
		
		open METAFLAC,"metaflac --list --block-type=VORBIS_COMMENT \"$File\" |";
		
		my $Album="";
		my $Artist="";
		my $ArtistSort="";
		my $Year="";
		my $Genre="";
		my @TrackArtist;
		my @TrackArtistSort;
		my @TrackTitle;
		my @TrackNumber;
		my $DiskNumber;
		my $Created=0;
		
		while (<METAFLAC>)
		{
			$Year=$1 if /DATE=(\d*)$/;
			
			$Year=$1 if /YEAR=(\d*)$/;
			
			$Album=$1 if /ALBUM=(.*)$/;
			
			$Artist=$1 if /ARTIST=(.*)$/;
			
			$ArtistSort=$1 if /ARTISTSORT=(.*)$/;
			
			$Genre=$1 if /GENRE=(.*)$/;
			
			$DiskNumber=$1 if /DISCNUMBER=(.*)$/;
			
			$TrackArtist[$1]=$2 if /ARTIST\[(\d*)\]=(.*)$/;
			
			$TrackArtistSort[$1]=$2 if /ARTISTSORT\[(\d*)\]=(.*)$/;
			
			$TrackTitle[$1]=$2 if /TITLE\[(\d*)\]=(.*)$/;
			
			$TrackNumber[$1]=$2 if /TRACKNUMBER\[(\d*)\]=(.*)$/;
		}
		
		close METAFLAC;
		
		if ($Artist eq "")
		{
			$Artist="Various Artists";
		}

		($MP3Dir,$MP3Base)=ParseFile($File,$SourceDir);
		$MP3Dir=$DestDir."/".$MP3Dir;
		
		my $TrackFile=sprintf("$MP3Dir/$MP3Base - %02d.mp3",$TrackNumber[$#TrackNumber]);
		
		if (-f "$TrackFile")
		{
		}
		else
		{
			$Created=1;
			
			print "File $TrackFile doesn't exist\n";
			
			if (!-d $MP3Dir)
			{
				MakeDirTree ($MP3Dir);
			}
			
			system "metaflac --export-cuesheet-to=\"$Flac.cue\" \"$Flac\"";
			my $RetVal=system "cuebreakpoints \"$Flac.cue\" | shntool split -n \"\" -d \"$MP3Dir\" -o cust ext=mp3 \{ lame --quiet --preset fast standard - %f \} \"$Flac\"";
			unlink "$Flac.cue";
			
			if ($RetVal==0)
			{
				for (my $count=0;$count<$#TrackNumber+1;$count++)
				{
					my $Number=$TrackNumber[$count];
					
	        my $OldFile=sprintf("$MP3Dir/%03d.mp3",$count);
					my $NewFile=sprintf("$MP3Dir/$MP3Base - %02d.mp3",$Number);

					print "Renaming $OldFile to $NewFile\n";
					
					unlink $NewFile;
					rename $OldFile,$NewFile;
				}

				unlink  "\"$Flac.cue\"";
			}
		}
		
		if (-f "$TrackFile")
		{
			for (my $count=0;$count<$#TrackNumber+1;$count++)
			{
				my $Number=$TrackNumber[$count];
        my $ThisTitle=$TrackTitle[$count];
        
        if ($ThisTitle)
        {
					my $NewFile=sprintf("$MP3Dir/$MP3Base - %02d.mp3",$Number);
	
					($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,
						$atime,$MP3MTime,$ctime,$blksize,$blocks)
							= stat($NewFile);
					
					if ($MP3MTime<$FlacMTime || $Created==1)
					{
						print "Tagging $NewFile\n";
						
						my $mp3=MP3::Tag->new($NewFile);
						$mp3->get_tags;
						
			      if (exists $mp3->{ID3v1}) 
			      {
							$mp3->{ID3v1}->remove_tag;
				    }
				    
						my $id3=$mp3->new_tag("ID3v2");
						
						$id3->add_frame("TIT2",$ThisTitle);
						$id3->add_frame("TALB",$Album);
						$id3->add_frame("TRCK",$Number);
						
						if ($TrackArtist[$count] && $TrackArtist[$count] ne $Artist)
						{
							$id3->add_frame("TPE1",$TrackArtist[$count]);
							
							if ($TrackArtistSort[$count])
							{
								$id3->add_frame("TSOP",$TrackArtistSort[$count]);
							}
								
							$id3->add_frame("TCMP","1");
						}
						else
						{
							$id3->add_frame("TPE1",$Artist);

							if ($ArtistSort)
							{
								$id3->add_frame("TSOP",$ArtistSort);
							}
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
			}
		}
		else
		{
			print "Whoops, $TrackFile doesn't exist\n";
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

$SourceDir=$ARGV[0];
$DestDir=$ARGV[1];

ScanFlacs($SourceDir);

foreach $Flac (@Flacs)
{
	ProcessFlac($Flac);
}
