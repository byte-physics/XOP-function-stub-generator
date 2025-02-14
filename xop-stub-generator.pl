#!/usr/bin/env perl
# Copyright: Thomas Braun, support (at) byte (minus) physics (dot) de
# License: 3-clause BSD, see https://opensource.org/licenses/BSD-3-Clause
# Version: 0.15
# Date: 4/7/2017
#
# Requirement: A recent Perl version, utags from https://github.com/universal-ctags/ctags, ctags must be in $PATH
#
# Purpose: From a specially crafted C header file, this script can generate all
# necessary (resource file, header, and function) stubs for creating a XOP for
# Igor Pro(tm).
#
# Note: Check carefully the output of this program. It is used as at the tool
# for the tool only ;)

use strict;
use warnings;

my $argc = @ARGV;          # get the number of arguments

my ($functionIsThreadSafe,$line,@array,$funcSig, $returnType,@argsName,@argsType,@argsFirst,@argsThird,@argsSecond,@argsPointer,$rest,$funcName,@args,$arg,$i,@tmp,$resourceContentWin, $resourceContentMac);
my ($resourceParamType,$resourceReturnType,$allParameters,$functionsWin,$functionsMac,$parameter,$allFunctionsWin,$allFunctionsMac,$argNumber,$funcIndex,$allCaseLines);
my ($registerFunctionBodyContent,$caseLine,$allCppParameters, $cppParamType,$functionSkeleton,$allFunctionSkeletons);
my ($cppResultType,$allStructs,$allDeclLines,$declLine,$hfileSkeleton);
my ($in, $out, $ctags);

if($argc < 1){
  print "Too less arguments";
  exit 1;
}

if ($^O eq "darwin")
{
  $ctags = "/usr/local/bin/ctags";
}
else
{
  $ctags = "ctags"
}

system($ctags, "--options=NONE", "--pattern-length-limit=0", "--totals=yes",  "--language-force=C", "--c-kinds=p", $ARGV[0]);

open $in, "<", "tags" or die "can not open file ctags";

our $commonHeader = "// autogenerated by xop-stub-generator.pl from $ARGV[0]\n";

our $resourceFileTemplateWin = <<EOF;
#include "XOPResources.h"      // Defines XOP-specific symbols.

1100 XOPF              // Describes functions added by XOP to IGOR.
BEGIN
%%functionDefinitions%%
0,                // NOTE: 0 required to terminate the resource.
END
EOF

our $resourceFileTemplateMac = <<EOF;
// vim: set ft=rc:
#include "XOPStandardHeaders.r"      // Defines XOP-specific symbols.

resource 'XOPF' (1100) {   // Describes functions added by XOP to IGOR.
  {
    %%functionDefinitions%%
  }
};
EOF

our $resourceFileFunctionDefinitionWin= <<EOF;

  // %%funcSig%%
  "%%funcName%%\\0",
  F_UTIL | F_EXTERNAL%%ADDFUNCCAT%%,    // Function category
  %%returnType%%,          // Return value type
%%parameterLine%%
  0,
EOF

our $resourceFileFunctionDefinitionMac = <<EOF;

  // %%funcSig%%
  "%%funcName%%",
  F_UTIL | F_EXTERNAL%%ADDFUNCCAT%%,    // Function category
  %%returnType%%,          // Return value type
  {
%%parameterLine%%
  },
EOF

our $resourceFileParameterLine = "%%argType%%,      // parameter %%argNumber%%";

our $registerFunctionTemplate= <<EOF;
#include "XOPStandardHeaders.h" // Include ANSI headers, Mac headers, IgorXOP.h, XOP.h and XOPSupport.h
#include "functions.h"

XOPIORecResult RegisterFunction()
{
  /*  NOTE:
    Some XOPs should return a result of NIL in response to the FUNCADDRS message.
    See XOP manual "Restrictions on Direct XFUNCs" section.
  */

  XOPIORecParam funcIndex = GetXOPItem(0);    /* which function invoked ? */
  XOPIORecResult returnValue = NIL;

  switch (funcIndex)
  {
%%caseLine%%
  }
  return returnValue;
}
EOF

our $registerFunctionCaseTemplate = <<EOF;
  case %%funcIndex%%:
    returnValue = reinterpret_cast<XOPIORecResult>(%%funcName%%);
    break;
EOF

our $hfileHeader = <<EOF;
#pragma once
#include "XOPStandardHeaders.h" // Include ANSI headers, Mac headers, IgorXOP.h, XOP.h and XOPSupport.h

XOPIORecResult RegisterFunction();

#pragma pack(2)		// All structures passed to Igor are two-byte aligned.
struct DPComplexNum {
	double real;
	double imag;
};
#pragma pack()		// Reset structure alignment to default.
EOF

our $hfileFunctionTemplate = <<EOF;

#pragma pack(2)  // All structures passed to Igor are two-byte aligned.
struct %%funcName%%Params
{
%%functionParamterLine%%
};
typedef struct %%funcName%%Params %%funcName%%Params;
#pragma pack()
EOF

our $functionBodyTemplate= <<EOF;

// %%funcSig%%
extern "C" int %%funcName%%(%%funcName%%Params *p)
{

  return 0;
}
EOF

our $functionDeclTemplate= <<EOF;

// %%funcSig%%
extern "C" int %%funcName%%(%%funcName%%Params *p);
EOF

$rest="";
$funcName="";
$returnType="";
$resourceContentWin="";
$resourceContentMac="";
$funcIndex=0;
$allCaseLines="";
$allStructs="";
$allDeclLines="";
$argNumber=0;

while($line = <$in>){

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
      $parameter =~ s/%%argType%%/  $resourceParamType/g;
      $parameter =~ s/%%argNumber%%/$argNumber/g;
      $allParameters .= "$parameter\n";

      # generate cpp file parameter lines

      $cppParamType = &convertParameterTypeForCPPFile($argsType[$i],$argsPointer[$i]);

      $allCppParameters = "  $cppParamType$argsName[$i];\n" . $allCppParameters;
    }

    # resource file

    $resourceReturnType = &convertParameterTypeForResourceFile($returnType,0);

    chomp($allParameters);

    # win
    $functionsWin = $resourceFileFunctionDefinitionWin;
    $functionsWin =~ s/%%funcSig%%/$funcSig/g;
    $functionsWin =~ s/%%funcName%%/$funcName/g;
    if($argNumber > 0)
    {
      $functionsWin =~ s/%%parameterLine%%/$allParameters/g;
    }
    else
    {
      $functionsWin =~ s/%%parameterLine%%\n//g;
    }
    $functionsWin =~ s/%%returnType%%/$resourceReturnType/g;
    if($functionIsThreadSafe){
      $functionsWin =~ s/%%ADDFUNCCAT%%/ | F_THREADSAFE/g;
    }
    else{
      $functionsWin =~ s/%%ADDFUNCCAT%%//g;
    }

    $allFunctionsWin .= $functionsWin;

    # mac
    $functionsMac = $resourceFileFunctionDefinitionMac;
    $functionsMac =~ s/%%funcSig%%/$funcSig/g;
    $functionsMac =~ s/%%funcName%%/$funcName/g;
    if($argNumber > 0)
    {
      $functionsMac =~ s/%%parameterLine%%/$allParameters/g;
    }
    else
    {
      $functionsMac =~ s/%%parameterLine%%\n//g;
    }
    $functionsMac =~ s/%%returnType%%/$resourceReturnType/g;
    if($functionIsThreadSafe){
      $functionsMac =~ s/%%ADDFUNCCAT%%/ | F_THREADSAFE/g;
    }
    else{
      $functionsMac =~ s/%%ADDFUNCCAT%%//g;
    }

    $allFunctionsMac .= $functionsMac;

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

    $declLine = $functionDeclTemplate;
    $declLine =~ s/%%funcName%%/$funcName/g;
    $declLine =~ s/%%funcSig%%/$funcSig/g;
    $allDeclLines .= $declLine;

    $funcIndex++;

    # h file
    if($functionIsThreadSafe){
      $allCppParameters .= "  UserFunctionThreadInfoPtr tp; // needed for thread safe functions\n"
    }
    $allCppParameters .= "  $cppResultType" . "result;";
    $hfileSkeleton = $hfileFunctionTemplate;
    $hfileSkeleton =~ s/%%functionParamterLine%%/$allCppParameters/g;
    $hfileSkeleton =~ s/%%funcName%%/$funcName/g;
    $allStructs .= $hfileSkeleton;
  }
}
  close($in);

  open $out, ">", "functions.rc" or die "can not open resource file";

  $resourceContentWin = $resourceFileTemplateWin;
  $resourceContentWin =~ s/%%functionDefinitions%%/$allFunctionsWin/;

  print $out $commonHeader;
  print $out $resourceContentWin;
  close($out);

  open $out, ">", "functions.r" or die "can not open resource file";

  $resourceContentMac = $resourceFileTemplateMac;
  $resourceContentMac =~ s/%%functionDefinitions%%/$allFunctionsMac/;

  print $out $commonHeader;
  print $out $resourceContentMac;
  close($out);

  open $out, ">", "functions.cpp" or die "can not open file";

  $registerFunctionBodyContent = $registerFunctionTemplate;
  $registerFunctionBodyContent =~ s/%%caseLine%%/$allCaseLines/;

  print $out $commonHeader;
  print $out $registerFunctionBodyContent;
  close($out);

  open $out, ">", "functionBodys.cpp" or die "can not open file";

  print $out $commonHeader;
  print $out $allFunctionSkeletons;

  close($out);

  open $out, ">", "functions.h" or die  "can not open file";

  print $out $commonHeader;
  print $out $hfileHeader;
  print $out $allStructs;
  print $out $allDeclLines;

  close($out);

sub convertParameterTypeForResourceFile{

  my ($type,$pointer) = @_;

  my (%types, $resourceType);

  $types{"variable"} = "NT_FP64";
  $types{"complex"} = "NT_FP64 | NT_CMPLX";
  $types{"string"}   = "HSTRING_TYPE";
  $types{"DFREF"} = "DATAFOLDER_TYPE";
  $types{"WAVE"} = "WAVE_TYPE";
  $types{"WAVEWAVE"} = "WAVE_TYPE";
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

  $types{"complex"} = "struct DPComplexNum";
  $types{"variable"} = "double";
  $types{"string"}   = "Handle";
  $types{"DFREF"} = "DataFolderHandle";
  $types{"WAVE"} = "waveHndl";
  $types{"WAVEWAVE"} = "waveHndl";
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
    $CType = "$CType ";
  }

  return $CType;
}
