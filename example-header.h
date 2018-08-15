/*
 * Author:  Thomas Braun, thomas dot braun aeht virtuell minus zuhause dot de
 * License: GPLv3 or later
 * Version: 0.12
 * Date: 4/20/2011
 *
 * Purpose: Example file for xop-stub-generator.pl
*/

variable openFile(string absoluteFilePath, string fileName);
string getBugReportTemplate();
THREADSAFE variable getFileName(string *filename);
string getValues(struct myStruct* s);
