# Author: Thomas Braun, thomas (dot) braun (at) virtuell-zuhause (dot) de
# License: GPLv3 or later
# Version: 0.12
# Date: 4/20/2011
#
# Requirement: A recent Perl version, utags from https://github.com/universal-ctags/ctags, ctags must be in $PATH
# Purpose: From a specially crafted C header file, this script can generate all necessary (resource file, header, and function) stubs for creating a XOP for Igor Pro(tm).
# Note: Check carefully the output of this program. It is used as at the tool for the tool only ;)
#

use strict;
use warnings;
use diagnostics;

my $argc = @ARGV;          # get the number of arguments

my ($functionIsThreadSafe,$line,@array,$funcSig, $returnType,@argsName,@argsType,@argsFirst,@argsThird,@argsSecond,@argsPointer,$rest,$funcName,@args,$arg,$i,@tmp,$resourceContent);
my ($resourceParamType,$resourceReturnType,$parameterLine,$allParameters,$functions,$parameter,$allFunctions,$argNumber,$funcIndex,$allCaseLines);
my ($registerFunctionBodyContent,$caseLine,$allCppParameters, $allFunctionSkeletonsi, $cppParamType,$functionSkeleton,$allFunctionSkeletons);
my ($cppResultType,$allhfileFuncSig,$hfileFuncSig,$hfileSkeleton);

if($argc < 1){
	print "Too less arguments";
	exit 1;
}

system("ctags.exe", "--pattern-length-limit=0", "--totals=yes",  "--language-force=C", "--c-kinds=+px-t", $ARGV[0]);

open(IN,"<tags") or die "can not open file ctags";


our $resourceFileTemplate = <<EOF;
// autogenerated by create-igor-xop-files.pl from $ARGV[0]
1100 XOPF							// Describes functions added by XOP to IGOR.
BEGIN
%%functionDefinitions%%
	0,								// NOTE: 0 required to terminate the resource.
END

EOF

our $resourceFileFunctionDefinition= <<EOF;
	// %%funcSig%%
	"%%funcName%%\\0",
	F_UTIL | F_EXTERNAL%%ADDFUNCCAT%%,		// Function category
	%%returnType%%,					// Return value type
%%parameterLine%%	0,

EOF

our $resourceFileParameterLine = "	%%argType%%,			// parameter %%argNumber%%";

our $registerFunctionTemplate= <<EOF;
static XOPIORecResult RegisterFunction()
{
	/*	NOTE:
		Some XOPs should return a result of NIL in response to the FUNCADDRS message.
		See XOP manual "Restrictions on Direct XFUNCs" section.
	*/

	int funcIndex = GetXOPItem(0);		/* which function invoked ? */
	XOPIORecResult returnValue = NIL;

	switch (funcIndex) {
%%caseLine%%
	}
	return returnValue;
}
EOF

our $registerFunctionCaseTemplate = <<EOF;
		case %%funcIndex%%:
			returnValue = (XOPIORecResult) %%funcName%%;
			break;
EOF

our $hfileFunctionTemplate = <<EOF;
#pragma pack(2)	// All structures passed to Igor are two-byte aligned.
struct %%funcName%%Params{
%%functionParamterLine%%
};
typedef struct %%funcName%%Params %%funcName%%Params;
#pragma pack()

EOF

our $functionBodyTemplate= <<EOF;

// %%funcSig%%
extern "C" int %%funcName%%(%%funcName%%Params *p){

	return 0;
}




EOF

$rest="";
$funcName="";
$returnType="";
$resourceContent="";
$funcIndex=0;
$allCaseLines="";
$allhfileFuncSig="";

while($line = <IN>){

	if( not ($line =~ m/^!/) ){ # ignore comments

		@array = split(/\//,$line);
		$funcSig = $array[1];
		$funcSig =~ s/^^\^//;
		$funcSig =~ s/;\$$//;

		print "function signature is $funcSig\n";

		if($funcSig =~ s/^THREADSAFE\s*//){
			$functionIsThreadSafe=1;
		}else{
			$functionIsThreadSafe=0;
		}

		($returnType,$rest) = split(/\ /,$funcSig,2);
		@tmp = split(/([()])/,$rest);

		$funcName = $tmp[0];

		# Trim whitespace from the front and end of the name
		$funcName =~ s/^\s+|\s+$//g;

		# Igor Pro only allows 31 chars as maximum function name length
		if(length($funcName) > 31){
			print "The functions name $funcName is too long. Only 31 chars are allowed.";
			return 0;
		}

		$rest = $tmp[2];

		print "function name $funcName\n";
		print "function return type $returnType\n";
		print "rest _ $rest _\n";

		undef @args;
		@args = split(/ *, */,$rest);

		$allParameters="";
		$allCppParameters="";
		for($i=0; $i < @args; $i++ ){

			$arg = $args[$i];

			if($arg =~ m/\*/){ # is a pointer
				$argsPointer[$i]=1;
			}
			else{
				$argsPointer[$i]=0;
			}

			# we don't know at which position (at the type, between spaces or in front of the variable name) the pointer is so we delete it now and add it afterwards in front of the variable
			$arg =~ s/\*//;

			($argsFirst[$i],$argsSecond[$i],$argsThird[$i]) = split(/ +/,$arg,3);

			# in case the third part is empty, we have as usual two components as in "int counter"
			if( !defined($argsThird[$i]) ){
				$argsType[$i] = $argsFirst[$i];
				$argsName[$i] = $argsSecond[$i];
			}
			# here the type has two components as in "struct someStructName myStruct"
			else{
				$argsType[$i] = $argsFirst[$i] . "  " . $argsSecond[$i];
				$argsName[$i] = $argsThird[$i];
			}

			print "type: $argsType[$i], name: $argsName[$i], pointer: $argsPointer[$i]\n";

			# generate resource file parameter lines

			$resourceParamType = &convertParameterTypeForResourceFile($argsType[$i],$argsPointer[$i]);
			$argNumber = $i+1;

			$parameter = $resourceFileParameterLine;
			$parameter =~ s/%%argType%%/$resourceParamType/g;
			$parameter =~ s/%%argNumber%%/$argNumber/g;
			$allParameters .= "$parameter\n";

			# generate cpp file parameter lines

			$cppParamType = &convertParameterTypeForCPPFile($argsType[$i],$argsPointer[$i]);

			$allCppParameters = "\t$cppParamType$argsName[$i];\n" . $allCppParameters;
		}

		# resource file

		$resourceReturnType = &convertParameterTypeForResourceFile($returnType,0);

		$functions = $resourceFileFunctionDefinition;
		$functions =~ s/%%funcSig%%/$funcSig/g;
		$functions =~ s/%%funcName%%/$funcName/g;
		$functions =~ s/%%parameterLine%%/$allParameters/g;
		$functions =~ s/%%returnType%%/$resourceReturnType/g;
		if($functionIsThreadSafe){
			$functions =~ s/%%ADDFUNCCAT%%/ | F_THREADSAFE/g;
		}
		else{
			$functions =~ s/%%ADDFUNCCAT%%//g;
		}

		$allFunctions .= $functions;

		print "\n\n";


		# cpp files

		$cppResultType = &convertParameterTypeForCPPFile($returnType,0);
		$functionSkeleton = $functionBodyTemplate;
		$functionSkeleton =~ s/%%funcName%%/$funcName/g;
		$functionSkeleton =~ s/%%funcSig%%/$funcSig/g;
		$allFunctionSkeletons .= $functionSkeleton;

		$caseLine = $registerFunctionCaseTemplate;
		$caseLine =~ s/%%funcIndex%%/$funcIndex/g;
		$caseLine =~ s/%%funcName%%/$funcName/g;

		$allCaseLines .= $caseLine;
		$funcIndex++;

		# h file
		if($functionIsThreadSafe){
			$allCppParameters .= "\tUserFunctionThreadInfoPtr tp; // needed for thread safe functions\n"
		}
		$allCppParameters .= "\t$cppResultType" . "result;";
		$hfileSkeleton = $hfileFunctionTemplate;
		$hfileSkeleton =~ s/%%functionParamterLine%%/$allCppParameters/g;
		$hfileSkeleton =~ s/%%funcName%%/$funcName/g;

		$hfileFuncSig = "int $funcName($funcName" . "Params *p);\n\n";
		$allhfileFuncSig .= $hfileSkeleton;
	}
}
	close(IN);

	open(OUT,">resourceFile.rc") or die "can not open resource file";

	$resourceContent = $resourceFileTemplate;
	$resourceContent =~ s/%%functionDefinitions%%/$allFunctions/;

	print OUT $resourceContent;
	close(OUT);

	open(OUT,">functionBodys.cpp") or die "can not open file";

	$registerFunctionBodyContent = $registerFunctionTemplate;
	$registerFunctionBodyContent =~ s/%%caseLine%%/$allCaseLines/;

	print OUT "\n\n";
	print OUT $allFunctionSkeletons;
	print OUT "\n\n";

	print OUT $registerFunctionBodyContent;

	close(OUT);

	open(OUT,">functionBodys.h") or die  "can not open file";

	print OUT "\n\n";
	print OUT $allhfileFuncSig;
	print OUT "\n\n";

	close(OUT);

sub convertParameterTypeForResourceFile{

	my ($type,$pointer) = @_;

	my (%types, $resourceType);

	$types{"variable"} = "NT_FP64";
	$types{"string"}   = "HSTRING_TYPE";
	$types{"WAVE"} = "WAVE_TYPE";
	$types{"TEXTWAVE"} = "WAVE_TYPE";
	$types{"FP64WAVE"} = "WAVE_TYPE";
	$types{"FP32WAVE"} = "WAVE_TYPE";
	$types{"INT8WAVE"} = "WAVE_TYPE";
	$types{"INT16WAVE"} = "WAVE_TYPE";
	$types{"INT32WAVE"} = "WAVE_TYPE";
	$types{"INT64WAVE"} = "WAVE_TYPE";
	$types{"UINT8WAVE"} = "WAVE_TYPE";
	$types{"UINT16WAVE"} = "WAVE_TYPE";
	$types{"UINT32WAVE"} = "WAVE_TYPE";
	$types{"UINT64WAVE"} = "WAVE_TYPE";

	if( $type =~ m/struct/){
		$resourceType =  "FV_REF_TYPE | FV_STRUCT_TYPE";
	}
	else{
		$resourceType = $types{$type};
		if($pointer == 1 ){
			$resourceType = "FV_REF_TYPE | $resourceType";
		}
	}

	return $resourceType;

}

sub convertParameterTypeForCPPFile{

	my ($type,$pointer)= @_;

	my (%types, $CType);

	$types{"variable"} = "double";
	$types{"string"}   = "Handle";
	$types{"WAVE"} = "waveHndl";
	$types{"TEXTWAVE"} = "waveHndl";
	$types{"FP64WAVE"} = "waveHndl";
	$types{"FP32WAVE"} = "waveHndl";
	$types{"INT8WAVE"} = "waveHndl";
	$types{"INT16WAVE"} = "waveHndl";
	$types{"INT32WAVE"} = "waveHndl";
	$types{"INT64WAVE"} = "waveHndl";
	$types{"UINT8WAVE"} = "waveHndl";
	$types{"UINT16WAVE"} = "waveHndl";
	$types{"UINT32WAVE"} = "waveHndl";
	$types{"UINT64WAVE"} = "waveHndl";

	if( $type =~ m/struct/){
		$CType =  $type
	}
	else{
		$CType = $types{$type};
	}

	if($pointer == 1 ){
		$CType = "$CType \*";
	}
	else{
		$CType = "$CType  ";
	}

	return $CType;
}
