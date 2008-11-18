#!/usr/bin/perl -w

use Audio::FLAC::Header;
use Audio::TagLib;

sub RemoveReplayGain
{
	foreach $ogg (@_)
	{
		$ogg->tag()->removeField(Audio::TagLib::String->new("REPLAYGAIN_ALBUM_GAIN","Latin1"));
		$ogg->tag()->removeField(Audio::TagLib::String->new("REPLAYGAIN_ALBUM_PEAK","Latin1"));
		$ogg->tag()->removeField(Audio::TagLib::String->new("REPLAYGAIN_TRACK_GAIN","Latin1"));
		$ogg->tag()->removeField(Audio::TagLib::String->new("REPLAYGAIN_TRACK_PEAK","Latin1"));
	}
}

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
	
	return sprintf("%02d - %s.ogg",$TrackNum,$TrackTitle);
}

sub ProcessSingleTrackFlac
{
	foreach $File (@_)
	{
		my $Created=0;
		
		print "Processing $File\n";
		
		($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,
			$atime,$FlacMTime,$ctime,$blksize,$blocks)
				= stat($File);
		
		my $srcfile = Audio::FLAC::Header->new($File);
		my $srcframes = $srcfile->tags();

		my $MaxTrack=0;
				
		my %GlobalTags;
		
		foreach $framename (keys %$srcframes)
		{
			if ($framename ne "COVERART" && $framename ne "VENDOR")
			{
				if ($framename=~/REPLAYGAIN/)
				{
					#print "Ignoring $framename\n";
				}
				else
				{
					$GlobalTags{$framename}=$srcframes->{$framename};
				}
			}
		}

		($MP3Dir,$MP3Base)=ParseFile($File,$SourceDir);
		$MP3Dir=$DestDir."/".$MP3Dir;

		my $TrackFile="$MP3Dir/$MP3Base.ogg";
		
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
			
			my $RetVal=system "flac -s -d -c \"$File\" | oggenc -Q -q 5 -o \"$TrackFile\" - ";
			#my $RetVal=system "flac -d -c \"$File\" | lame --quiet --preset fast standard - \"$TrackFile\"";
		}
		
		if (-f "$TrackFile")
		{
			($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,
				$atime,$MP3MTime,$ctime,$blksize,$blocks)
					= stat($TrackFile);
			
			
			if ($MP3MTime<$FlacMTime || $Created==1)
			{
				print "Tagging $TrackFile\n";
						
				my $ogg = Audio::TagLib::Ogg::Vorbis::File->new($TrackFile);
				
				RemoveReplayGain($ogg);
				
				foreach $GlobalTag (keys %GlobalTags)
				{
					$Name = Audio::TagLib::String->new($GlobalTag,"Latin1");
					$Value = Audio::TagLib::String->new($GlobalTags{$GlobalTag},"UTF8");
					$ogg->tag()->addField($Name,$Value);
				}
		
				$ogg->save();
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
		my $Created=0;
		
		($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,
			$atime,$FlacMTime,$ctime,$blksize,$blocks)
				= stat($File);
		
		my $srcfile = Audio::FLAC::Header->new($File);
		my $srcframes = $srcfile->tags();

		my $MaxTrack=0;
				
		my %GlobalTags;
		my @TrackTags;
		
		foreach $framename  (keys %$srcframes)
		{
			if ($framename ne "COVERART" && $framename ne "VENDOR")
			{
				if ($framename=~/REPLAYGAIN/)
				{
					#print "Ignoring $framename\n";
				}
				else
				{
					if ($framename=~/(.*)\[(.*)\]/)
					{
						if ($2>$MaxTrack)
						{
							$MaxTrack=$2;
						}
					
						$TrackTags[$2]{$1}=$srcframes->{$framename};
					}
					else
					{
						$GlobalTags{$framename}=$srcframes->{$framename};
					}
				}
			}
		}

		#foreach $tag (keys %GlobalTags)
		#{
		#	print "'" . $tag . "' is '" . $GlobalTags{$tag} . "'\n";
		#}
		
		#next;
		
		($MP3Dir,$MP3Base)=ParseFile($File,$SourceDir);
		$MP3Dir=$DestDir."/".$MP3Dir;
		
		my $TrackFile=sprintf("$MP3Dir/$MP3Base - %02d.ogg",$MaxTrack);
		
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
			my $RetVal=system "cuebreakpoints \"$Flac.cue\" 2>/dev/null | shntool split -n \"\" -d \"$MP3Dir\" -o cust ext=ogg \{ oggenc -q 5 -o %f - \}  \"$Flac\"";
			#my $RetVal=system "cuebreakpoints \"$Flac.cue\" | shntool split -n \"\" -d \"$MP3Dir\" -o cust ext=mp3 \{ lame --quiet --preset fast standard - %f \} \"$Flac\"";
			unlink "$Flac.cue";
			
			if ($RetVal==0)
			{
				for (my $Number=1;$Number<=$MaxTrack;$Number++)
				{
	        my $OldFile=sprintf("$MP3Dir/%03d.ogg",$Number);
					my $NewFile=sprintf("$MP3Dir/$MP3Base - %02d.ogg",$Number);

					print "Renaming $OldFile to $NewFile\n";
					
					unlink $NewFile;
					rename $OldFile,$NewFile;
				}
			}
		}
		
		if (-f "$TrackFile")
		{
			for (my $Track=1;$Track<=$MaxTrack;$Track++)
			{
				my $NewFile=sprintf("$MP3Dir/$MP3Base - %02d.ogg",$Track);

				($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,
					$atime,$MP3MTime,$ctime,$blksize,$blocks)
						= stat($NewFile);
				
				if ($MP3MTime<$FlacMTime || $Created==1)
				{
					print "Tagging $NewFile\n";
					
					my $ogg = Audio::TagLib::Ogg::Vorbis::File->new($NewFile);

					RemoveReplayGain($ogg);					

					foreach $TrackTag (keys %{$TrackTags[$Track]})
					{
						$Name = Audio::TagLib::String->new($TrackTag,"Latin1");
						$Value = Audio::TagLib::String->new($TrackTags[$Track]{$TrackTag},"UTF8");
						$ogg->tag()->addField($Name,$Value);
					}

					foreach $GlobalTag (keys %GlobalTags)
					{
						if ($TrackTags[$Track]{$GlobalTag})
						{
							#print "Not tagging with global tag $GlobalTag - in Track Tags\n";
						}
						else
						{
							$Name = Audio::TagLib::String->new($GlobalTag,"Latin1");
							$Value = Audio::TagLib::String->new($GlobalTags{$GlobalTag},"UTF8");
							$ogg->tag()->addField($Name,$Value);
						}
					}
			
					$ogg->save();
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

$Count=1;

@Sorted=sort(@Flacs);

foreach $Flac (@Sorted)
{
	print $Count;
	print " of ";
	print $#Flacs+1;
	print " - ";
	print $Flac;
	print "\n";
	$Count++;
	
	ProcessFlac($Flac);
}
