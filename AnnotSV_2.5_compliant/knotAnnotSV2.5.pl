#!/usr/bin/perl

##############################################################################################
# knotAnnotSV 1.0                                                                            #	
#                                                                                            #
# knotAnnotSV: Creation of a customizable html file to visualize, filter                   	 # 
#                   and analyze an AnnotSV output                                            #
#                                                                                            #
# Author: Thomas Guignard 2020                                                               #
#                                                                                            #
# Copyright (C) 2020 Thomas Guignard (t-guignard@chu-montpellier.fr)                         #
#                                                                                            #
# This is part of knotAnnotSV source code.        	                                         #
#                                                                                            #
# This program is free software; you can redistribute it and/or                              #
# modify it under the terms of the GNU General Public License                                #
# as published by the Free Software Foundation; either version 3                             #
# of the License, or (at your option) any later version.                                     #
#                                                                                            #
# This program is distributed in the hope that it will be useful,                            #
# but WITHOUT ANY WARRANTY; without even the implied warranty of                             #
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the                              #
# GNU General Public License for more details.                                               #
#                                                                                            #
# You should have received a copy of the GNU General Public License                          #
# along with this program; If not, see <http://www.gnu.org/licenses/>.                       #
##############################################################################################


use strict; 
use warnings;
use Getopt::Long; 
use YAML::XS 'LoadFile';
use Sort::Key::Natural qw(rnatkeysort);
use File::Basename;

#use Switch;
#use Data::Dumper;

#parameters
my $man = "USAGE : \nperl knotAnnotSV.pl 
\n--configFile <YAML config file for customizing output>
\n--annotSVfile <AnnotSV annotated file> 
\n--outDir <output directory (default = current dir)> 
\n--outPrefix <output file prefix (default = \"\")> 
\n--genomeBuild <Genome Assembly reference (default = hg19)> 
\n--LOEUFcolorRange <Number to define which color to use for LOEUF bin:  1(red-to-green), 2(red-shades-only)  (default = 1)> 
\n--datatableDir <Local Path to dataTables directory containing css and js files (default = \"\", requires web connection)>"; 


my $configFile = ".";

my $help;
my $current_line;
my $incfile = "";
my $outDir = ".";
my $outPrefix = "";
my $annotSVranking = "";
my $datatableDir = "";
my $LOEUFcolorRange = "";

#vcf parsing and output
my @line;
my $variantID; 
my $count = 0;

my @finalSortData;
my %hashFinalSortData;
	
my $config;
my %columnHash;
my %InColHash;
my %OutColHash;
my %NameColHash;
my %dataHash;
my %dataCommentHash;
my %dataColorHash;

my $scorePenalty;
my $scorePenaltySplit;
my $fullSplitScore;
my %SV_ID;
my $SV_type;
my $fullRowColor;

my $url2UCSC="";
my $url2OMIM="";
my $url2DECIPHER="";
my $url2ensembl="";

my $genomeBuild="";
#style alignment for tooltiptext
my $alignTooltiptext="";

GetOptions( "annotSVfile=s"		=> \$incfile,
			"configFile=s"		=> \$config,
			"outDir=s"			=> \$outDir,
			"outPrefix:s"		=> \$outPrefix,
			"datatableDir=s"	=> \$datatableDir,
			"genomeBuild=s"		=> \$genomeBuild,
			"LOEUFcolorRange=s"	=> \$LOEUFcolorRange,
			"help|h"			=> \$help);
				
				


#check mandatory arguments
if(defined $help || $incfile eq ""){
	die($man."\n");
}

#add underscore to output prefix
if($outPrefix ne ""){
	$outPrefix .= "_";
}

#check datatable pathname
if ($datatableDir ne "" && ! -d $datatableDir){
    print "\nError with datatableDir argument: ".$datatableDir." is not an existing directory.\n\n";
    exit 1;    
}
			
#check if genomeBuild exists (hg19 grch37 hg38, mm etc..) and put hg19 as default build 
if($genomeBuild eq ""){
	$genomeBuild = "hg19";
}


#open( CONFIG, "<$config" ) or die ("Cannot open vcf file $config") ;

#CONFIG FILE PARSING
print STDERR "Parsing config file....\n";
my %configHash;
my $configHash;
my $OutColCounter = 0;
my $outPOSITION = 0; 
$configHash = LoadFile($config);
	#print Dumper($configHash);


foreach my $item (keys %{$configHash}){
		#print $item."\n";
		my $field = $item;
		#print $configHash->{$field}->{POSITION}."\n";

        if ($configHash->{$field}->{POSITION} != 0 && defined $OutColHash{$configHash->{$field}->{POSITION}}){
            print "\nError in config file: 'POSITION : ".$configHash->{$field}->{POSITION}."' is assigned twice.\nPlease correct config file to avoid 2 identical positions.\n\n";
            exit 1;
        }else {
		    if ($configHash->{$field}->{POSITION} != 0){
				#$OutColHash{$configHash->{$field}->{POSITION}} = $field;
				$outPOSITION = $configHash->{$field}->{POSITION};
				$OutColHash{$outPOSITION}{'field'} = $field;
				#$OutColHash{$configHash->{$field}->{POSITION}}{'field'} = $field;
				$OutColCounter ++;

            }
		    $NameColHash{$field} = $configHash->{$field}->{POSITION};
			#TODO $NameColHash{$field}{'POSITION'} = $configHash->{$field}->{POSITION};
			
			if (defined $configHash->{$field}->{COMMENTLIST}){
				$dataCommentHash{$field}{'commentFieldList'}=$configHash->{$field}->{COMMENTLIST} ;
			}
			#get custom name for column
			if (defined $configHash->{$field}->{RENAME}){
			#$NameColHash{$field}{'RENAME'} = $configHash->{$field}->{RENAME};
				$OutColHash{$configHash->{$field}->{POSITION}}{'RENAME'} = $configHash->{$field}->{RENAME};
			}else{
			#$NameColHash{$field}{'RENAME'} = $field;
				$OutColHash{$configHash->{$field}->{POSITION}}{'RENAME'} = $field;
			}
			#get custom string for column header tooltip
			if (defined $configHash->{$field}->{HEADERTIPS}){
				#$NameColHash{$field}{'HEADERTIPS'} = $configHash->{$field}->{HEADERTIPS};
				$OutColHash{$configHash->{$field}->{POSITION}}{'HEADERTIPS'} = $configHash->{$field}->{HEADERTIPS};
			}
        }
		
		#print Dump($field)."\n";
}


#ANNOTSV RANKING PARSING to get ranking decision
my @SVrankLine;
my %SVrankHash;

if ($annotSVranking ne ""){
	open( SVRANK , "<$annotSVranking" )or die("Cannot open ranking file ".$annotSVranking."\n") ;
	
	
	while( <SVRANK> ){

		chomp $_;
		@SVrankLine = split( /\t/, $_ );	

		if (defined $SVrankHash{$SVrankLine[0]."_".$SVrankLine[2]}){
			print "Doublon detected in ranking file : ".$_."\n\n";
		}else{
			$SVrankHash{$SVrankLine[0]."_".$SVrankLine[2]} = $SVrankLine[4];
		}	
	}

	#add comment with rank to AnnotSV ranking column
	if (! defined $dataCommentHash{'AnnotSV ranking'}{'commentFieldList'}){
		$dataCommentHash{'AnnotSV ranking'}{'SVrank'} = "OK";
	}

}





#Hash of ACMG incidentalome genes  => grey color #808080
my %ACMGgene = ("ACTA2" =>1,"ACTC1" =>1,"APC" =>1,"APOB" =>1,"ATP7B" =>1,"BMPR1A" =>1,"BRCA1" =>1,"BRCA2" =>1,"CACNA1S" =>1,"COL3A1" =>1,"DSC2" =>1,"DSG2" =>1,"DSP" =>1,"FBN1" =>1,"GLA" =>1,"KCNH2" =>1,"KCNQ1" =>1,"LDLR" =>1,"LMNA" =>1,"MEN1" =>1,"MLH1" =>1,"MSH2" =>1,"MSH6" =>1,"MUTYH" =>1,"MYBPC3" =>1,"MYH11" =>1,"MYH7" =>1,"MYL2" =>1,"MYL3" =>1,"NF2" =>1,"OTC" =>1,"PCSK9" =>1,"PKP2" =>1,"PMS2" =>1,"PRKAG2" =>1,"PTEN" =>1,"RB1" =>1,"RET" =>1,"RYR1" =>1,"RYR2" =>1,"SCN5A" =>1,"SDHAF2" =>1,"SDHB" =>1,"SDHC" =>1,"SDHD" =>1,"SMAD3" =>1,"SMAD4" =>1,"STK11" =>1,"TGFBR1" =>1,"TGFBR2" =>1,"TMEM43" =>1,"TNNI3" =>1,"TNNT2" =>1,"TP53" =>1,"TPM1" =>1,"TSC1" =>1,"TSC2" =>1,"VHL" =>1,"WT1"=>1);


#initialize gene colore according to pLI/LOEUF
#my %pLI_ColorHash;
#my $pLI_Color;

#$pLI_ColorHash{'0.9'} = '#FF0000';
#$pLI_ColorHash{'0.8'} = '#FF3300';
#$pLI_ColorHash{'0.7'} = '#FF6600';
#$pLI_ColorHash{'0.6'} = '#FF9900';
#$pLI_ColorHash{'0.5'} = '#FFCC00';
#$pLI_ColorHash{'0.4'} = '#FFFF00';
#$pLI_ColorHash{'0.3'} = '#BFFF00';
#$pLI_ColorHash{'0.2'} = '#7FFF00';
#$pLI_ColorHash{'0.1'} = '#3FFF00';
#$pLI_ColorHash{'0.0'} = '#00FF00';


#Select and initialize color Range for LOEUF bin
my %LOEUF_ColorHash;
my $LOEUF_Color;
if($LOEUFcolorRange eq "" ||$LOEUFcolorRange == 1 ){
	$LOEUF_ColorHash{'0.0'} = '#FF0000';
	$LOEUF_ColorHash{'1.0'} = '#FF3300';
	$LOEUF_ColorHash{'2.0'} = '#FF6600';
	$LOEUF_ColorHash{'3.0'} = '#FF9900';
	$LOEUF_ColorHash{'4.0'} = '#FFCC00';
	$LOEUF_ColorHash{'5.0'} = '#FFFF00';
	$LOEUF_ColorHash{'6.0'} = '#BFFF00';
	$LOEUF_ColorHash{'7.0'} = '#7FFF00';
	$LOEUF_ColorHash{'8.0'} = '#3FFF00';
	$LOEUF_ColorHash{'9.0'} = '#00FF00';

}elsif($LOEUFcolorRange == 2){
	$LOEUF_ColorHash{'0.0'} = '#FF0606';
	$LOEUF_ColorHash{'1.0'} = '#FF3737';
	$LOEUF_ColorHash{'2.0'} = '#FF5050';
	$LOEUF_ColorHash{'3.0'} = '#FF6363';
	$LOEUF_ColorHash{'4.0'} = '#FF6F6F';
	$LOEUF_ColorHash{'5.0'} = '#FF8888';
	$LOEUF_ColorHash{'6.0'} = '#FF9B9B';
	$LOEUF_ColorHash{'7.0'} = '#FFB4B4';
	$LOEUF_ColorHash{'8.0'} = '#FFD9D9';
	$LOEUF_ColorHash{'9.0'} = '#FFF2F2';

}else{
	die("LOEUFcolorRange argument is unacceptable: ".$LOEUFcolorRange."\n") ;
}

####################################################################
#############################################
##################   Start parsing VCF

open( VCF , "<$incfile" )or die("Cannot open annotSV file ".$incfile."\n") ;

my ($outBasename,$dir,$ext) = fileparse($incfile,'\.tsv$');


while( <VCF> ){
  	$current_line = $_;
	$count++;


	chomp $current_line;
	@line = split( /\t/, $current_line );	
	

#############################################
##############   Treatment for First line to create header of the output

	if ( $line[0] eq "AnnotSV ID" )   {
		
		#TODO check if header contains required INFO
		print STDERR "Parsing AnnotSV header in order to get column names ... \n";

		#initialize column order
		for( my $fieldNbr = 0 ; $fieldNbr < scalar @line; $fieldNbr++){
			
			#print STDERR "Field found:  ".$line[$fieldNbr]."\n";
			$InColHash{$fieldNbr} = $line[$fieldNbr];
			
			$dataHash{$line[$fieldNbr]} = ".";
			
		}

		next;
		
#############################################
##############################
##########  start to compute variant lines	

	}else {

		#initialise final printable string
		@finalSortData = ("");
		#$pLI_Color=".";
		$LOEUF_Color=".";

        #fill nbr of SV_ID;
        if (defined $SV_ID{$line[0]} ){
            $SV_ID{$line[0]}{'nbr'}++;
        }else{
            $SV_ID{$line[0]}{'nbr'} = 1;
        }
        
		#reinitialize Comment Values
		foreach my $field (keys %dataCommentHash){
			delete $dataCommentHash{$field}{'values'};
		}


		#fill printable string
		for( my $fieldNbr = 0 ; $fieldNbr < scalar @line; $fieldNbr++){
			
			if($line[$fieldNbr] ne ""){
				$line[$fieldNbr] =~ s/;/; /g ;  
				$line[$fieldNbr] =~ s/\//\/ /g ;  
				$dataHash{$InColHash{$fieldNbr}} = $line[$fieldNbr] ; 
				

			}else{
				$dataHash{$InColHash{$fieldNbr}} = ".";
			}

		}

		#get SVtype
		$SV_type = $dataHash{'SV type'};

		#check what type among different writting allowed
		if ($SV_type =~ /DUP|GAIN|CN[3-9]/i){
			$SV_type = "DUP";
			$fullRowColor = "#DFE9FF";
		}elsif ($SV_type =~ /DEL|LOSS|CN[0-1]/i){
			$SV_type = "DEL";
			$fullRowColor = "#F7D8DD";
		}elsif ($SV_type =~ /INV/i){
			$SV_type = "INV";
			$fullRowColor = "#FFFFCD";
		}elsif ($SV_type =~ /BND/i){
			$SV_type = "BND";
			$fullRowColor = "#D2F8E3";
		}else{
			$fullRowColor = "#ffffff";
		}

		

		#hash to avoid duplicated comments for DGV LOSS and GAIN
		my %commentDuplicate;
		my $correctFieldCom;

		#get all comments values
		foreach my $field (keys %dataCommentHash){
            #print $field."\n";
			#if (defined $dataCommentHash{$field})
			#	foreach my $fieldCom (@{$dataCommentHash{$field}{'commentFieldList'}})
			if (defined $dataCommentHash{$field}){
                if (! defined $dataCommentHash{$field}{'values'}){
					#special treatment for DGV field , adding to comment the switched name
					if ( $field =~ /^DGV_/){
						if ($SV_type eq "DEL" ){ 
							$correctFieldCom = $field =~ s/GAIN/LOSS/r;
							$commentDuplicate{$correctFieldCom} += 1;	
						}elsif ($SV_type eq "DUP" ){ 
							$correctFieldCom = $field =~ s/LOSS/GAIN/r;
							$commentDuplicate{$correctFieldCom} += 1;	
						}else{
							$correctFieldCom = $field;
						}
						#add in first line of comment
               		 	$dataCommentHash{$field}{'values'} .= "<span class=\"commentTitle\">".$correctFieldCom . " :</span> ".$dataHash{$correctFieldCom};
					}
				
				    foreach my $fieldCom (@{$dataCommentHash{$field}{'commentFieldList'}}){
					    if (defined $dataHash{$fieldCom}){
							if ( $fieldCom =~ /^DGV_/){
								if ($SV_type eq "DEL" ){ 
									$correctFieldCom = $fieldCom =~ s/GAIN/LOSS/r;
									$commentDuplicate{$correctFieldCom} += 1;	
								}elsif ($SV_type eq "DUP" ){ 
									$correctFieldCom = $fieldCom =~ s/LOSS/GAIN/r;
									$commentDuplicate{$correctFieldCom} += 1;	
								}else{
									$correctFieldCom = $fieldCom;
								}
								if (defined $commentDuplicate{$fieldCom} && $commentDuplicate{$fieldCom} > 1){
									next;
								}
								#print $field."_".$correctFieldCom."\n";
                            	$dataCommentHash{$field}{'values'} .= "<br><span class=\"commentTitle\">".$correctFieldCom . " :</span> ".$dataHash{$correctFieldCom};
							}else{
                            	$dataCommentHash{$field}{'values'} .= "<br><span class=\"commentTitle\">".$fieldCom . " :</span> ".$dataHash{$fieldCom};
							}

                        }else{
                            print $field."\n";
                            $dataCommentHash{$field}{'values'} .= "<br><span class=\"commentTitle\">".$fieldCom . " :</span> Absent in file";
                        }
                        #print $field.":\t".$fieldCom.":\t".$dataCommentHash{'Gene name'}{'values'}."\n";
				    }
			    }
				
				# add ranking decision as comment of AnnotSV ranking field
				#if (defined $dataCommentHash{$field}{'SVrank'}){
	  			#	if (defined $SVrankHash{$dataHash{'AnnotSV ID'}."_".$dataHash{'Gene name'}}){
                #		if (! defined $dataCommentHash{$field}{'values'}){
				#			$dataCommentHash{$field}{'values'}= "<br><b>Ranking :</b> " . $SVrankHash{$dataHash{'AnnotSV ID'}."_".$dataHash{'Gene name'}} ;
				#		}else{
				#			$dataCommentHash{$field}{'values'} = "<br><b>Ranking :</b> " .$SVrankHash{$dataHash{'AnnotSV ID'}."_".$dataHash{'Gene name'}} . $dataCommentHash{$field}{'values'};  	
				#		}
				#	}
				#}
			}
		}


		my $correctField;

		#fill finalSortData array   (try to invert foreach with NameColHash for external name)
		foreach my $field (keys %dataHash){
				
			if (defined $NameColHash{$field} && $NameColHash{$field} != 0){
				
				if ( $field =~ /^DGV_/){

					if ($SV_type eq "DEL" ){ 
						$correctField = $field =~ s/GAIN/LOSS/r;
						$finalSortData[$NameColHash{$field} - 1] = $dataHash{$correctField};
					}elsif ($SV_type eq "DUP" ){
						$correctField = $field =~ s/LOSS/GAIN/r;
						$finalSortData[$NameColHash{$field} - 1] = $dataHash{$correctField};
					}else{
						$finalSortData[$NameColHash{$field} - 1] = $dataHash{$field};
					}
				}else{
					$finalSortData[$NameColHash{$field} - 1] = $dataHash{$field};
            	}
			}
		}


		#fill color LOEUF bin (old=pLI) 
		foreach my $field (keys %dataHash){
			#if (defined $dataHash{'pLI_ExAC'} ){
			if (defined $dataHash{'LOEUF_bin'} ){
                foreach my $bin (sort {$b <=> $a} keys %LOEUF_ColorHash){
                    if ( $dataHash{'LOEUF_bin'} eq "."){
                        $LOEUF_Color = '#FFFFFF';
                        last;
                    }
                    if ( $dataHash{'LOEUF_bin'}  >= $bin){
                        $LOEUF_Color = $LOEUF_ColorHash{$bin};
                        last;
                    }
                }
			}else{
                $LOEUF_Color = '#FFFFFF';            
            }
		}
        
		#change LOEUF color if ACMG gene
		if (defined $ACMGgene{$dataHash{'Gene name'}}){
			$LOEUF_Color = '#808080';
		}



		# check if column names and data have the same size
		#if (scalar @finalSortData != keys %OutColHash){
		if (scalar @finalSortData != $OutColCounter){
			print "\nError in config file: it seems that some POSITION are missing.\nPlease correct config file with continuous 'POSITION' number.\n\n"; 
			exit 1;
		}

		
		#	print Dumper(\@finalSortData);

#############################################################################
######### FILL HASH STRUCTURE WITH COMMENTS 
		
		    
            $variantID = $line[0];

			#key for good sorting should be rank concatenated with annotSV_ID
			#
			#grant full line to be first
			if ($dataHash{"AnnotSV type"} eq "full"){
				#TODO compute CNV penalty
				#$scorePenalty = ".1";	
				$scorePenalty = $dataHash{"AnnotSV ranking"};	
				#if (defined $SV_ID{$dataHash{'AnnotSV ID'}}{'finalScore'}){
				$SV_ID{$dataHash{'AnnotSV ID'}}{'finalScore'} = $scorePenalty;
				#$SV_ID{$dataHash{'AnnotSV ID'}}{'splitScore'} = $dataHash{"AnnotSV ranking"} + 1000;
				$scorePenaltySplit = 1000;	
				$fullSplitScore = 1000;
			}else{
				#TODO compute gene penalty
				$scorePenaltySplit = 0;	
				$fullSplitScore = 0;
			}

			#finalsortData assigment according to full or split
			$hashFinalSortData{$SV_ID{$dataHash{'AnnotSV ID'}}{'finalScore'}."_".$variantID}{$dataHash{'AnnotSV ID'}}{$dataHash{"AnnotSV ranking"}+$fullSplitScore}{$count}{'finalArray'} = [@finalSortData] ; 

			#finalsortData assigment
			#$hashFinalSortData{$dataHash{"AnnotSV ranking"}.$scorePenalty."_".$variantID}{$count}{'finalArray'} = [@finalSortData] ; 




			
			#url to UCSC for SV , highlight in blue and zoomout x1.5
			$hashFinalSortData{$SV_ID{$dataHash{'AnnotSV ID'}}{'finalScore'}."_".$variantID}{$dataHash{'AnnotSV ID'}}{$dataHash{"AnnotSV ranking"}+$fullSplitScore}{$count}{'url2UCSC'} = "http://genome.ucsc.edu/cgi-bin/hgTracks?db=".$genomeBuild."&position=chr".$dataHash{"SV chrom"}.":".$dataHash{"SV start"}."-".$dataHash{"SV end"}."&hgt.out1=submit&highlight=".$genomeBuild.".chr".$dataHash{"SV chrom"}.":".$dataHash{"SV start"}."-".$dataHash{"SV end"}."#aaedff\" target=\"_blank\" rel=\"noopener noreferrer\"" ; 

			#url to OMIM
			$hashFinalSortData{$SV_ID{$dataHash{'AnnotSV ID'}}{'finalScore'}."_".$variantID}{$dataHash{'AnnotSV ID'}}{$dataHash{"AnnotSV ranking"}+$fullSplitScore}{$count}{'url2OMIM'} = "https://www.omim.org/entry/".$dataHash{"Mim Number"}  ; 



			#comment assigment
			foreach my $fieldCom (keys %dataCommentHash){
				$hashFinalSortData{$SV_ID{$dataHash{'AnnotSV ID'}}{'finalScore'}."_".$variantID}{$dataHash{'AnnotSV ID'}}{$dataHash{"AnnotSV ranking"}+$fullSplitScore}{$count}{'hashComments'}{$NameColHash{$fieldCom} -1} = $dataCommentHash{$fieldCom}{'values'} ; 
				#print $dataCommentHash{'Gene name'}{'values'}."\n\n";
				#TODO check color for gene according to output position of gene field 
			}


            #assign color to Gene Name
			$hashFinalSortData{$SV_ID{$dataHash{'AnnotSV ID'}}{'finalScore'}."_".$variantID}{$dataHash{'AnnotSV ID'}}{$dataHash{"AnnotSV ranking"}+$fullSplitScore}{$count}{'hashColor'}{$NameColHash{'Gene name'}-1} = $LOEUF_Color ;



            #assign color to Gene Name
			$hashFinalSortData{$SV_ID{$dataHash{'AnnotSV ID'}}{'finalScore'}."_".$variantID}{$dataHash{'AnnotSV ID'}}{$dataHash{"AnnotSV ranking"}+$fullSplitScore}{$count}{'fullRowColor'} = $fullRowColor ;




	} #END of IF-ELSE(#CHROM)	

}#END WHILE VCF


#prepare path to lib css and js


#original url used
#'https://code.jquery.com/jquery-3.5.1.js'
#'https://cdn.datatables.net/1.10.22/js/jquery.dataTables.min.js'
#'https://cdn.datatables.net/fixedheader/3.1.7/js/dataTables.fixedHeader.min.js'
#'https://cdn.datatables.net/fixedcolumns/3.3.2/js/dataTables.fixedColumns.min.js'

#'https://cdn.datatables.net/1.10.22/css/jquery.dataTables.min.css'
#'https://cdn.datatables.net/fixedheader/3.1.7/css/fixedHeader.dataTables.min.css'
#'https://cdn.datatables.net/fixedcolumns/3.3.2/css/fixedColumns.dataTables.min.css'


my $path2jquery = "https://code.jquery.com/";
my $path2jqueryDT = "https://cdn.datatables.net/1.10.22/js/";
my $path2jsFCDT = "https://cdn.datatables.net/fixedcolumns/3.3.2/js/";

my $path2css = "https://cdn.datatables.net/1.10.22/css/"; 
my $path2FCcss = "https://cdn.datatables.net/fixedcolumns/3.3.2/css/";

if ($datatableDir ne ""){

	#remove trailing slash from path
	$datatableDir =~ s/\/$//;

	$path2jquery = $datatableDir."/js/";
	$path2jqueryDT = $datatableDir."/js/";

	$path2css = $datatableDir."/css/"; 
	$path2FCcss = $datatableDir."/css/";
}





############ THE TIME HAS COME TO FILL THE HTML OUTPUT FILE
####################################################################
######################### HTML  Initialisation ######################
#
#file header
my $htmlStart = "<!DOCTYPE html>\n<html>
\n<head>
\n<meta charset=\"utf-8\">
\n<title>".$outPrefix.$outBasename."</title>\n
\n<script type=\"text/javascript\" language=\"javascript\" src='".$path2jquery."jquery-3.5.1.js'></script>
\n<script type=\"text/javascript\" language=\"javascript\" src='".$path2jqueryDT."jquery.dataTables.min.js'></script>
\n<script type=\"text/javascript\" language=\"javascript\" src='".$path2jsFCDT."dataTables.fixedColumns.min.js'></script>
\n<script type=\"text/javascript\" > 


var openTab;

//document ready
\$(document).ready(function() {
				var height = \$(window).height();
				var h = Math.floor(height - 250);
				var filterHash = new Object();
				var keyType = \"".($NameColHash{'AnnotSV type'} - 1)."\";
				var keyAnnotID = \"".($NameColHash{'AnnotSV ID'} - 1)."\";
				var fullMode = 'full';	
				var dblClickMode = 'off';	
				var oldStart = 0;

				//input FILTER
				var head = '#tabFULLSPLIT thead';
				\$(head+' tr').clone(true).appendTo(head);
	
				\$(head+' tr:eq(1) th').each( function (i) {
					\$(this).removeClass('sorting').removeClass('sorting_asc').removeClass('sorting_desc');
					\$(this).unbind();
					let title = \$(this).text();
					\$(this).html( '<input id=\"col'+i+'\" type=\"text\" placeholder=\"Search\" data-index=\"'+i+'\" />' );
				}); //END FILTER



				//INITIALISATION
				var tabFULLSPLIT = \$('#tabFULLSPLIT').DataTable({
					stateSave: true,
					stateDuration: 0,
					order: [],
					paging: true,
					orderCellsTop: true,
					scrollX: true,
					scrollY: h,
					scrollCollapse: true,
					oLanguage: { sLengthMenu: 'Show _MENU_ lines',sInfo: 'Showing _START_ to _END_ of _TOTAL_ lines' },
					lengthMenu: [
							[50, 100, -1],
							[50, 100, 'All']
						],
					fixedColumns:   {
						leftColumns: 1,
						heightMatch: 'auto',
					 },
					stateLoadParams: function( settings, data ) {
						filterHash = data.filter;
						fullMode = data.fullMode ;	
						dblClickMode = data.dblClickMode ;	
						//console.log('load__');
					},
					stateSaveParams: function( settings, data ) {
						data.filter = filterHash;	
						data.fullMode = fullMode;	
						data.dblClickMode = dblClickMode;	
						//console.log('save__');
					},
					drawCallback: function (o) {
						var newStart = this.api().page.info().start;
						if ( newStart != oldStart ) {
							\$('.dataTables_scrollBody').scrollTop(0);
							oldStart = newStart;
						}
					},
			});  //END initialisation

			//FILTER FUNCTION
			\$(tabFULLSPLIT.table().container() ).on( 'keyup change', 'thead input', function (){ 

						//console.log('toto1');
						var expr = this.value;
						var i = \$(this).data('index');
						if(/^[!<>=]+\$/.test(expr)){
							return;
						}
						
						if(expr === ''){
							delete filterHash[i] ;
						}else{

							var exprClean = expr.replace(/\\s*/g, '');
							filterHash[i] = new Object();
							filterHash[i]['raw'] = exprClean;
							if (/^[!<>=]/.test(expr)) {
								var oper = expr.match(/^([!<>=]+)/);
								var exp = exprClean.match(/^\\W+([-]?\\w+[.]?\\w*)/i);
								filterHash[i]['operator'] = oper[0];
								if (exp === null){
									return;
								}
								filterHash[i]['expr'] = exp[1];

							}else{
								filterHash[i]['operator'] = '==';
								filterHash[i]['expr'] = new RegExp(`\${exprClean}`,'i');
							}
						}

						tabFULLSPLIT.draw();
					
					});
					

			//button tab		
			var tabs = `<div class=\"tab\" style=\"float: left;\">
								<button id=\"FULLbutton\" class=\"tablinks active\" onclick=\"openTab(event, 'full')\">COMPACT</button>
								<button id=\"FULLSPLITbutton\" class=\"tablinks\" onclick=\"openTab(event, 'fullsplit')\">EXPANDED</button>
							</div>`;
			\$('#tabFULLSPLIT_wrapper').prepend(tabs);
			

				//double click expand
				\$('#tabFULLSPLIT tbody').on('dblclick', 'tr', function () {
					var rowID = this.id;			
					var fm = fullMode;
					if (rowID !== '' && fullMode === 'full'){

						if (dblClickMode == 'off'){
							dblClickMode = 'on';
							\$('#tabFULLSPLIT_wrapper .DTFC_LeftWrapper thead tr:eq(1) th:eq('+keyAnnotID+') input', \$('.tooltipHeader td')[keyAnnotID] ).val(rowID);
							\$('#tabFULLSPLIT_wrapper .dataTables_scrollHead thead tr:eq(1) th:eq('+keyType+') input', \$('.tooltipHeader td')[keyType] ).val('' );
							filterHash[keyAnnotID] = new Object();
							filterHash[keyAnnotID]['raw'] = rowID;
							filterHash[keyAnnotID]['operator'] = '==';
							filterHash[keyAnnotID]['expr'] = new RegExp(`\${filterHash[keyAnnotID]['raw']}`,'i');
							delete filterHash[keyType] ;

						}else{
							dblClickMode = 'off';
							\$('#tabFULLSPLIT_wrapper .dataTables_scrollHead thead tr:eq(1) th:eq('+keyType+') input', \$('.tooltipHeader td')[keyType] ).val('full' );
							\$('#tabFULLSPLIT_wrapper .DTFC_LeftWrapper thead tr:eq(1) th:eq('+keyAnnotID+') input', \$('.tooltipHeader td')[keyAnnotID] ).val('');
							filterHash[keyType] = new Object();
							filterHash[keyType]['raw'] = 'full';
							filterHash[keyType]['operator'] = '==';
							filterHash[keyType]['expr'] = new RegExp(`\${filterHash[keyType]['raw']}`,'i');
							delete filterHash[keyAnnotID] ;

						}
						
						tabFULLSPLIT.draw();

					}
				} ); //END DOUBLE CLICK

				//FILTERING FUNCTION PUSH AT INITIALISATION
				\$.fn.dataTableExt.afnFiltering.push(
					function( oSettings, aData, iDataIndex ) {
						var filtHash = filterHash;
						var filtBool = true;
						for (var keys in filtHash){
							if (filtHash.hasOwnProperty(keys)) {
								var row_data = aData[keys];
			
								switch (filtHash[keys]['operator']){
									case '>': if(row_data > filtHash[keys]['expr']) {filtBool = true;continue;}else{ return false;}
									case '<': if(row_data < filtHash[keys]['expr']) {filtBool = true;continue;}else{ return false;}
									case '>=': if(row_data >= filtHash[keys]['expr']) {filtBool = true;continue;}else{ return false;}
									case '<=': if(row_data <= filtHash[keys]['expr']) {filtBool = true;continue;}else{ return false;}
									case '!=': if(row_data != filtHash[keys]['expr']) {filtBool = true;continue;}else{ return false;}
									case '<>': if(row_data != filtHash[keys]['expr']) {filtBool = true;continue;}else{ return false;}
									case '=': if(row_data == filtHash[keys]['expr']) {filtBool = true;continue;}else{ return false;}
									case '==': var m = row_data.match(filtHash[keys]['expr']); if(m === null){return false;}else{filtBool = true;continue;}
								}
							}
						}
			
						return filtBool;
					}); //END function filterByExp




				//Restore state				
				var state = tabFULLSPLIT.state.loaded();						 
				if ( state  ) {
					//console.log('state__');
					for (var keys in filterHash){
						if (filterHash.hasOwnProperty(keys)) {
							\$('#tabFULLSPLIT_wrapper .dataTables_scrollHead thead tr:eq(1) th:eq('+keys+') input', \$('.tooltipHeader td')[keys] ).val( filterHash[keys]['raw'] );
							if (filterHash[keys]['operator'] == '=='){
								filterHash[keys]['expr'] = new RegExp(`\${filterHash[keys]['raw']}`,'i');
							}
						}
					}
					if (fullMode == 'fullsplit'){
						\$('#FULLbutton').removeClass('active');
						\$('#FULLSPLITbutton').addClass('active');
                                        }
					if (dblClickMode == 'on'){
						\$('#tabFULLSPLIT_wrapper .DTFC_LeftWrapper thead tr:eq(1) th:eq('+keyAnnotID+') input', \$('.tooltipHeader td')[keyAnnotID] ).val(filterHash[keyAnnotID]['raw']);
					}

					
					
					tabFULLSPLIT.draw();
				}else{  //END restore
					
					//FULL view on load	
					window.onload =	\$('#tabFULLSPLIT_wrapper .dataTables_scrollHead thead tr:eq(1) th:eq('+keyType+') input', \$('.tooltipHeader td')[keyType] ).val('full' ).change();			
				}


		


	//click full split button
	openTab =	function(evt, cityName) {
				
				if(cityName === 'full'){
				
					fullMode = 'full';

					filterHash[keyType] = new Object();
					filterHash[keyType]['raw'] = cityName;
					filterHash[keyType]['operator'] = '==';
					filterHash[keyType]['expr'] = new RegExp(`\${filterHash[keyType]['raw']}`,'i');
					
					\$('#FULLSPLITbutton').removeClass('active');
					\$('#FULLbutton').addClass('active');
					
					\$('#tabFULLSPLIT_wrapper .dataTables_scrollHead thead tr:eq(1) th:eq('+keyType+') input', \$('.tooltipHeader td')[keyType] ).val(cityName );
					
				}else{
					
					fullMode = 'fullsplit';

					delete filterHash[keyType] ;
					\$('#FULLbutton').removeClass('active');
					\$('#FULLSPLITbutton').addClass('active');
					\$('#tabFULLSPLIT_wrapper .dataTables_scrollHead thead tr:eq(1) th:eq('+keyType+') input', \$('.tooltipHeader td')[keyType] ).val('');

				}
				
				if (dblClickMode == 'on'){
					dblClickMode = 'off';
					\$('#tabFULLSPLIT_wrapper .DTFC_LeftWrapper thead tr:eq(1) th:eq('+keyAnnotID+') input', \$('.tooltipHeader td')[keyAnnotID] ).val('');
					delete filterHash[keyAnnotID] ;
				}
	
				
				\$('#tabFULLSPLIT').DataTable().draw();
			}


			



});  //END document ready




</script>
\n<link rel=\"stylesheet\" type=\"text/css\" href='".$path2css."jquery.dataTables.min.css'>
\n<link rel=\"stylesheet\" type=\"text/css\" href='".$path2FCcss."fixedColumns.dataTables.min.css'>

\n<style>
/* Style the tab */
	.tab {
		overflow: hidden;
		border: 1px solid #ccc;
		background-color: #f1f1f1;
		left: 0;
		bottom: 0;
		height: 27px;
		position: fixed;
		position: -webkit-sticky;
		position: sticky;
		margin-right: 10px;
		}

/* Style the buttons inside the tab */
	.tab button {
		background-color: inherit;
		float: left;
		border: none;
		outline: none;
		cursor: pointer;
		transition: 0.3s;
		font-size: 17px;
		height: 27px;
		}
/* Change background color of buttons on hover */
	.tab button:hover {
		background-color: #ddd;
		}

/* Create an active/current tablink class */
	.tab button.active {
		background-color: #ccc;
		}
	.tab button:focus {
		background-color: #ccc;
		}

	td {
		text-align: center;
		}
	thead input {
		width: 100%;
		}

	#tabFULLSPLIT.display td.sorting_1{
		background-color: inherit;
	}

	table.dataTable.display tbody tr.odd > .sorting_1, table.dataTable.order-column.stripe tbody tr.odd > .sorting_1{
		background-color: inherit; 
	}
	table.dataTable.display tbody tr.even > .sorting_1, table.dataTable.order-column.stripe tbody tr.even > .sorting_1{
		background-color: inherit; 
	}



/* Style the tab content */
	.tabcontent {
		display: block;
		padding: 6px 12px;
		/*border: 1px solid #ccc;*/
		border-top: none;
		}

	.tooltipHeader{
		position: relative;
		font-size: 90%;
		cursor: help;
	}		
	.tooltipHeader .tooltiptext{
		visibility: hidden;
		width: auto;
		min-width: 250px;
		max-width: 800px;
		height: auto;
		background-color: #1e1e1e;
		color: #fff;
		text-align: left;
		border-radius: 6px;
		padding: 5px 5px;
		position: absolute;
		z-index: 1;
		top: -5px;
		opacity: 0;
		transition: opacity 0.3s;
		text-overflow: ellipsis;
		white-space: normal;
		overflow-wrap: break-word;
		}
	.tooltipHeader:hover .tooltiptext{
		visibility: visible;
		opacity: 1;
	}	

	.tooltip {
		position: relative;
		display: inline-block;
		/*border-bottom: 1px dotted black;*/
		min-width: 100px;
		max-width: 300px;
		overflow-wrap: break-word;
		font-size: 70%;
		}
	
	.tooltip .tooltiptext {
		visibility: hidden;
		width: auto;
		min-width: 250px;
		max-width: 290px;
		max-height: 469px;
		background-color: #1e1e1e;
		color: #fff;
		text-align: left;
		border-radius: 6px;
		padding: 5px 5px;
		position: absolute;
		z-index: 1;
		top: 100%;
		opacity: 0;
		transition: opacity 0.3s;
		text-overflow: ellipsis;
		white-space: normal;
		overflow-wrap: break-word;
		font-size: 100%;
		overflow-y: scroll;
		}

	.tooltip:hover .tooltiptext {
		visibility: visible;
		opacity: 1;
		}
		
	.commentTitle {
		color: #FF69B4; 
		font-weight: bold;
	}


	div.dataTables_wrapper {
		width: 100%;
	/*	margin: 0 auto;*/
	}
	.DTFC_LeftBodyLiner { overflow-x: hidden; }
	.DTFC_RightBodyLiner { overflow-x: hidden; }




\n</style>

\n</head>
\n\t<body>\n\n<div> <h2>".$outPrefix.$outBasename."___".$genomeBuild."</h2></div>";

#table and columns names


my $htmlALL= "<div id=\"FULL+SPLIT\" class=\"tabcontent\">";
$htmlALL .= "\n\t<table id='tabFULLSPLIT' class='display compact' >
        \n\t\t<thead>\n\t\t\t<tr>";


foreach my $col (sort {$a <=> $b} keys %OutColHash){
			#print HTML "\t<th style=\"word-wrap: break-word\"   >";
	if (defined $OutColHash{$col}{'field'}){
		if (defined $OutColHash{$col}{'HEADERTIPS'}){
			#adjust tooltip position relativelly to column number
			if ($col <= ($OutColCounter/2)){
				
				if($col == 1){
					$alignTooltiptext = "style=\"left: 1%;max-width:250px\"";
				}else{
					$alignTooltiptext = "style=\"left: ".int(($OutColCounter-($col*2))*100/$OutColCounter)."%\"";
				}
			}else{
				$alignTooltiptext = "style=\"right: ".int(($col*2-$OutColCounter)*100/$OutColCounter)."%\"";
			}

			$htmlALL .= "\t<th class=\"tooltipHeader\" >".$OutColHash{$col}{'RENAME'}."<span ".$alignTooltiptext." class=\"tooltiptext tooltip-bottom\">".$OutColHash{$col}{'HEADERTIPS'}."</span> \t</th>\n";
		}else{
			$htmlALL .= "\t<th class=\"tooltipHeader\">".$OutColHash{$col}{'RENAME'}."\t</th>\n";
		}
	}
}


$htmlALL .= "\n\t\t\t</tr>\n\t\t</thead>\n\t<tbody>\n";
					

my $htmlEndTable = "\t</tbody>\n\t</table>\n\t\t</div>\n\n\n";
					
my $htmlEnd = "\n\t</body>\n</html>";



open(HTML, '>', $outDir."/".$outPrefix.$outBasename.".html") or die $!;


#########################################################################
#################### Sort by AnnotSV ranking for the output

#create user friendly ranking score
my $kindRank=0;


# check if last line was "FULL" to finish the raw with </tr>


foreach my $rank (rnatkeysort { "$_-$hashFinalSortData{$_}" } keys %hashFinalSortData){
	print $rank."\n";
	
	foreach my $ID ( keys %{$hashFinalSortData{$rank}}){
		
		#foreach my $rankSplit (sort {$hashFinalSortData{$rank}{$ID}{$b} <=> $hashFinalSortData{$rank}{$ID}{$a} } ( keys %{$hashFinalSortData{$rank}{$ID}})){
		foreach my $rankSplit (rnatkeysort { "$_-$hashFinalSortData{$rank}{$ID}{$_}" }  keys %{$hashFinalSortData{$rank}{$ID}}){
	
			foreach my $variant ( keys %{$hashFinalSortData{$rank}{$ID}{$rankSplit}}){
			
			#increse rank number then change final array
			$kindRank++;
		

			#FILL tab 'ALL';
			if (    $hashFinalSortData{$rank}{$ID}{$rankSplit}{$variant}{'finalArray'}[$NameColHash{'AnnotSV type'} - 1] eq "full") {
				$htmlALL .= "<tr id=\"".$ID."\" class=\"full\" style=\"background-color:".$hashFinalSortData{$rank}{$ID}{$rankSplit}{$variant}{'fullRowColor'}."\" >\n";
			}else{
				$htmlALL .= "<tr class=\"fullsplit ".$ID."\" >\n";
			}

			#Once for "ALL"  = FULL+SPLIT
			for( my $fieldNbr = 0 ; $fieldNbr < scalar @{$hashFinalSortData{$rank}{$ID}{$rankSplit}{$variant}{'finalArray'}} ; $fieldNbr++){
				#print $fieldNbr."\n";
				#print $hashFinalSortData{$rank}{$variant}{'finalArray'}[$fieldNbr]."\n";

	
				#implementing rowspan only if line is "full" type
				# TODO loop on finalArray with counter to skip first td SVID for split line
				#if (     $hashFinalSortData{$rank}{$variant}{'finalArray'}[$NameColHash{'AnnotSV type'} - 1] eq "full") {
       
					
				if (defined $hashFinalSortData{$rank}{$ID}{$rankSplit}{$variant}{'hashColor'}{$fieldNbr}){
					if ($hashFinalSortData{$rank}{$ID}{$rankSplit}{$variant}{'finalArray'}[$NameColHash{'location'} - 1] eq "txStart-txEnd" || $hashFinalSortData{$rank}{$ID}{$rankSplit}{$variant}{'finalArray'}[$NameColHash{'location'} - 1] eq ".") {
						$htmlALL .= "\t<td style=\"background-color:".$hashFinalSortData{$rank}{$ID}{$rankSplit}{$variant}{'hashColor'}{$fieldNbr}."\" ";

					}else{

						if ($hashFinalSortData{$rank}{$ID}{$rankSplit}{$variant}{'finalArray'}[$NameColHash{'location'} - 1] =~ /^txStart/) {
							$htmlALL .= "\t<td style=\"background: linear-gradient(-45deg, white 50%, ".$hashFinalSortData{$rank}{$ID}{$rankSplit}{$variant}{'hashColor'}{$fieldNbr}." 50% )\" ";
						}else{
							$htmlALL .= "\t<td style=\"background: linear-gradient(-45deg,".$hashFinalSortData{$rank}{$ID}{$rankSplit}{$variant}{'hashColor'}{$fieldNbr}." 50%, white 50% )\" ";

						}
					}

				}else{
					if ($fieldNbr eq $NameColHash{'AnnotSV ID'} - 1){
						$htmlALL .= "\t<td data-order=\"".$kindRank."\" ";	
					}else{
						$htmlALL .= "\t<td ";
					}
				}
					#$htmlALL .= "\t<td rowspan=\".$hashFinalSortData{$rank}{$variant}{SVIDNbr}."\">";
					#}


				#define search field
				$htmlALL .= "data-search=\"".$hashFinalSortData{$rank}{$ID}{$rankSplit}{$variant}{'finalArray'}[$fieldNbr] ."\">";

				#if (defined $field){
				if (defined $hashFinalSortData{$rank}{$ID}{$rankSplit}{$variant}{'finalArray'}[$fieldNbr]){
					#print HTML $field;

					#Add url to UCSC browser
					if ($fieldNbr eq $NameColHash{'AnnotSV ID'} - 1){
						$htmlALL .= "<div class=\"tooltip\"><a href=\"".$hashFinalSortData{$rank}{$ID}{$rankSplit}{$variant}{'url2UCSC'}."\">".$hashFinalSortData{$rank}{$ID}{$rankSplit}{$variant}{'finalArray'}[$fieldNbr]."</a>";
					}else{
							if( length($hashFinalSortData{$rank}{$ID}{$rankSplit}{$variant}{'finalArray'}[$fieldNbr]) > 50 ){
								$htmlALL .= "<div class=\"tooltip\">".substr($hashFinalSortData{$rank}{$ID}{$rankSplit}{$variant}{'finalArray'}[$fieldNbr],0,45)."[...]";
							}else{
								$htmlALL .= "<div class=\"tooltip\">".$hashFinalSortData{$rank}{$ID}{$rankSplit}{$variant}{'finalArray'}[$fieldNbr];
							}	

					}

					#adjust tooltip position relativelly to column number
					if (($fieldNbr+1) <= ($OutColCounter/2)){
						if (($fieldNbr+1) == 1){
							$alignTooltiptext = "style=\"height: 469px; left: 1%\"";
						}else{
							$alignTooltiptext = "style=\"left: ".int(($OutColCounter-($fieldNbr+1)*2)*100/$OutColCounter)."%\"";
						}
					}else{
						$alignTooltiptext = "style=\"right: ".int((($fieldNbr+1)*2-$OutColCounter)*100/$OutColCounter)."%\"";
					}


					if ($OutColHash{$fieldNbr + 1}{'field'} =~ /^DGV_/){
						$htmlALL .= "<span ".$alignTooltiptext." class=\"tooltiptext tooltip-bottom\">";
					}else{
						$htmlALL .= "<span ".$alignTooltiptext." class=\"tooltiptext tooltip-bottom\"><span class=\"commentTitle\">".$OutColHash{$fieldNbr + 1}{'field'}. " :</span> ".$hashFinalSortData{$rank}{$ID}{$rankSplit}{$variant}{'finalArray'}[$fieldNbr];
					}
					# add comments
					if (defined $hashFinalSortData{$rank}{$ID}{$rankSplit}{$variant}{'hashComments'}{$fieldNbr}){
						$htmlALL .= $hashFinalSortData{$rank}{$ID}{$rankSplit}{$variant}{'hashComments'}{$fieldNbr}."</span></div>";   
					}else{
					$htmlALL .= "</span></div>";
					}

				#	$hashFinalSortData{$rank}{$variant}{'hashComments'}{$NameColHash{$fieldCom}} 

				}else {
					#print HTML "."
					$htmlALL .= "."
				}
				#print HTML "\t</td>\n";
				$htmlALL .= "\t</td>\n";
			} #END FOR FULL+SPLIT tab


			#end of table line
			$htmlALL .= "</tr>\n";
	
	
			}   # END FOREACH VARIANT
		}   # END FOREACH RANKSPLIT
	}   # END FOREACH ID
}	#END FOREACH RANK



close(VCF);



#Write in HTML file
print HTML $htmlStart;
print HTML $htmlALL;
print HTML $htmlEndTable;
print HTML $htmlEnd;


close(HTML);




print STDERR "\n\n\nDone!\n\n\n";





exit 0; 


