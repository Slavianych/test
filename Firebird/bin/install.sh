#!/bin/sh
#
#  The contents of this file are subject to the Initial
#  Developer's Public License Version 1.0 (the "License");
#  you may not use this file except in compliance with the
#  License. You may obtain a copy of the License at
#  http://www.ibphoenix.com/main.nfs?a=ibphoenix&page=ibp_idpl.
#
#  Software distributed under the License is distributed AS IS,
#  WITHOUT WARRANTY OF ANY KIND, either express or implied.
#  See the License for the specific language governing rights
#  and limitations under the License.
#
#  The Original Code was created by Mark O'Donohue
#  for the Firebird Open Source RDBMS project.
#
#  Copyright (c) Mark O'Donohue <mark.odonohue@ludwig.edu.au>
#  and all contributors signed below.
#
#  All Rights Reserved.
#  Contributor(s): ______________________________________.
#		Alex Peshkoff
#

#  Install script for FirebirdSQL database engine
#  http://www.firebirdsql.org

parseArgs ${*}

checkInstallUser

BuildVersion=3.0.10.33601
PackageVersion=0
CpuType=amd64

Version="$BuildVersion-$PackageVersion.$CpuType"

if [ ! -z "$InteractiveInstall" ]
then
    cat <<EOF

Firebird $Version Installation

EOF

    AskQuestion "Press Enter to start installation or ^C to abort"
fi

# Here we are installing from a install tar.gz file

MANIFEST_TXT=`pwd`/manifest.txt
origDir=`pwd`

# It's good idea not to have running firebird/interbase instances
checkIfServerRunning

# Make sure we have required libraries installed
checkLibraries

# Archive any files we find
archivePriorInstallSystemFiles

# Extract installation archive
extractBuildroot

# Update /etc/services
newLine="gds_db          3050/tcp  # Firebird SQL Database Remote Protocol"
replaceLineInFile /etc/services "$newLine" "^gds_db"

# add Firebird user
if [ $RunUser = firebird ]; then
	addFirebirdUser
fi

# Set correct fb prefix in installed files
setNewPrefix

# Update ownership for files.
fixFilePermissions

# Prepare for uninstall
buildUninstallFile

# Create links to libraries in system lib directory
createLinksInSystemLib

# Create libgds.so links
createLinksForBackCompatibility

# Install script in /etc/init.d (exact location is distro dependent)
installInitdScript

# Add sysdba and set password (use embedded access)
setDBAPassword

# start the RDBMS server
startFirebird

displayMessage "Install completed"
