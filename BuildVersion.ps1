################################################################################
# File: 
#   BuildVersion.ps1
# Authors:
#   Wesley Buchanan
#   Tyler Matijevich
#   Connor Trostel
# Date: 
#   2022-03-21
################################################################################

###############
# Note to users
###############
# Please edit the "Parameters" section just below as you see fit
# Pre-build event field (also in README):
# PowerShell -ExecutionPolicy ByPass -File $(WIN32_AS_PROJECT_PATH)\Logical\BuildVersion\BuildVersion.ps1 $(WIN32_AS_PROJECT_PATH) "$(AS_VERSION)" "$(AS_USER_NAME)" "$(AS_PROJECT_NAME)" "$(AS_CONFIGURATION)" "$(AS_BUILD_MODE)"

$ScriptName = $MyInvocation.MyCommand.Name
Write-Host "BuildVersion: Running $ScriptName powershell script"

############
# Parameters
############
# The script will search under Logical to find this program (e.g. .\Logical\BuildVersion\BuildVer)
$ProgramName = "BuildVer"
# The script will search under Logical to find this variable file (e.g. .\Logical\Global.var)
$GlobalDeclarationName = "Global.var"
# The script will search for variables of this type
$TypeIdentifier = "BuildVersionType"

# Use $True or $False to select options
# Create build error if the script fails to due missing arguments
$OptionErrorOnArguments = $False
# Create build error if git is not installed or no git repository is found in project root
$OptionErrorOnRepositoryCheck = $False 
# Create build error if uncommitted changes are found in git repository
$OptionErrorOnUncommittedChanges = $False
# Create build error if neither a local or global variable is initialized with version information
$OptionErrorIfNoInitialization = $False

#################
# Check arguments
#################

if($args.Length -lt 1) {
    # Write-Warning output to the Automation Studio console is limited to 110 characters (AS 4.11.5.46 SP)
    Write-Warning "BuildVersion: Missing project path argument `$(WIN32_AS_PROJECT_PATH)"
    if($OptionErrorOnArguments) { exit 1 } 
    exit 0
}

# Debug
# for($i = 0; $i -lt $args.Length; $i++) {
#     $ArgumentValue = $args[$i]
#     Write-Host "Argument $i : $ArgumentValue"
# }

######################
# Search and set paths
######################

# Search for program
$LogicalPath = $args[0] + "\Logical\"
if(-not [System.IO.Directory]::Exists($LogicalPath)) {
    $Path = $args[0]
    Write-Warning "BuildVersion: Cannot find Logical folder in $Path"
    if($OptionErrorOnArguments) { exit 1 } 
    exit 0
}
# Get all directories named $ProgramName
$Search = Get-ChildItem -Path $LogicalPath -Filter $ProgramName -Recurse -Directory -Name
$ProgramFound = $False
# Loop through zero or more directories named $ProgramName
foreach($SearchItem in $Search) {
    $ProgramPath = $LogicalPath + $SearchItem + "\"
    # Search for any file in this directory with extension .prg
    $SubSearch = Get-ChildItem -Path $ProgramPath -Filter "*.prg" -Name
    # If there is at least one *.prg file assume Automation Studio program
    if($SubSearch.Count -ne 0) {
        $ProgramFound = $True
        $RelativeProgramPath = $ProgramPath.Replace($LogicalPath, ".\Logical\")
        Write-Host "BuildVersion: Located $ProgramName program at $RelativeProgramPath"
        break
    }
}
if(-NOT $ProgramFound) {
    Write-Warning "BuildVersion: Unable to locate $ProgramName in $LogicalPath"
}

# Search for global variable declaration file
$Search = Get-ChildItem -Path $LogicalPath -Filter $GlobalDeclarationName -Recurse -File -Name 
$GlobalFileFound = $False
foreach($SearchItem in $Search) {
    $GlobalFile = $LogicalPath + $SearchItem
    $GlobalFileFound = $True
    $RelativeGlobalFile = $GlobalFile.Replace($LogicalPath, ".\Logical\")
    Write-Host "BuildVersion: Located $GlobalDeclarationName at $RelativeGlobalFile"
    # Only take the first Global.var found
    break
}
if(-not $GlobalFileFound) {
    # This is only informational because a global variable declaration is optional
    Write-Host "BuildVersion: Unable to locate $GlobalDeclarationName in $LogicalPath"
}

$BuildDate = Get-Date -Format "yyyy-MM-dd-HH:mm:ss"

###########
# Functions
###########

# Truncate strings to match size of type declaration
function TruncateString {
    param ([String]$String,[Int]$Length)
    $String.Substring(0,[System.Math]::Min($Length,$String.Length))
}

################################################################################
################################################################################
################################################################################
# Git Commands
################################################################################
################################################################################
################################################################################

# Is git command available? Use `git version`
try {git version *> $Null} 
catch {
    Write-Warning "BuildVersion: Git in not installed or unavailable in PATH environment"
    if($OptionErrorOnRepositoryCheck) { exit 1 }
    else { exit 0 }
}

# Is the project in a repository? Use `git config --list --local`
git -C $args[0] config --list --local *> $Null 
if($LASTEXITCODE -ne 0) {
    Write-Warning "BuildVersion: No local repository has been found in the project root"
    if($OptionErrorOnRepositoryCheck) { exit 1 }
    else { exit 0 }
}

############
# Remote URL
############
# References:
# https://reactgo.com/git-remote-url/

$Url = git -C $args[0] config --get remote.origin.url 2> $Null
if($LASTEXITCODE -ne 0) {
    Write-Warning "BuildVersion: Git repository has no remote or differs from ""origin"""
    $Url = "Unknown"
}
$Url = TruncateString $Url 255

########
# Branch
########
# References:
# https://stackoverflow.com/a/12142066 

$Branch = git -C $args[0] branch --show-current 2> $Null
if($LASTEXITCODE -ne 0) {
    Write-Warning "BuildVersion: Local repository is in a headless state"
    $Branch = "Unknown"
}
$Branch = TruncateString $Branch 80

###################################
# Tag, Additional Commits, Describe
###################################
# References:
# "Most recent tag" https://stackoverflow.com/a/7261049
# "Catching exceptions" https://stackoverflow.com/a/32287181
# "Suppressing outputs" https://stackoverflow.com/a/57548278

$Tag = git -C $args[0] describe --tags --abbrev=0 2> $Null
if($LASTEXITCODE -ne 0) {
    Write-Warning "BuildVersion: No tags have been created on this branch"
    $Tag = "None"
    $Describe = "None"
    $AdditionalCommits = 0
    $Version = "None"
}
else {
    $Describe = git -C $args[0] describe --tags --long 2> $Null
    if($Describe.Replace($Tag,"").Split("-").Length -ne 3) {
        Write-Warning "BuildVersion: Unable to determine # of additional commits"
        $AdditionalCommits = 0
        $Version = $Tag
    }
    else {
        $AdditionalCommits = $Describe.Replace($Tag,"").Split("-")[1]
        $Version = $Tag + "-" + $AdditionalCommits
    }
}
$Tag = TruncateString $Tag 80
$Describe = TruncateString $Describe 80

######
# Sha1
######
# References:
# https://www.systutorials.com/how-to-get-the-latest-git-commit-sha-1-in-a-repository/

$Sha1 = git -C $args[0] rev-parse HEAD 2> $Null
if($LASTEXITCODE -ne 0) {
    Write-Warning "BuildVersion: Unable to determine latest secure hash"
    $Sha1 = "Unknown"
}
$Sha1 = TruncateString $Sha1 80

#####################
# Uncommitted Changes
#####################

$UncommittedChanges = git -C $args[0] diff --shortstat 2> $Null
$ChangeWarning = 1
if($UncommittedChanges.Length -eq 0) {
    $UncommittedChanges = "None"
    $ChangeWarning = 0
}
elseif($OptionErrorOnUncommittedChanges) {
    Write-Warning "BuildVersion: Uncommitted changes detected"
    exit 1
}
$UncommittedChanges = TruncateString $UncommittedChanges.Trim() 80

######
# Date
######

$GitDate = git -C $args[0] log -1 --format=%cd --date=iso 2> $Null
if($LASTEXITCODE -ne 0) {
    Write-Warning "BuildVersion: Unable to determine latest commit date"
    $CommitDate = "2000-01-01-00:00:00"
}
else {$CommitDate = Get-Date $GitDate -Format "yyyy-MM-dd-HH:mm:ss"}

##############################
# Commit Author Name and Email
##############################
# References:
# https://stackoverflow.com/a/41548774

$CommitAuthorName = git -C $Args[0] log -1 --pretty=format:'%an' 2> $Null
$CommitAuthorEmail = git -C $Args[0] log -1 --pretty=format:'%ae' 2> $Null
if($LASTEXITCODE -ne 0) {
    Write-Warning "BuildVersion: Unable to determine latest commit author"
    $CommitAuthorName = "Unknown"
    $CommitAuthorEmail = "Unknown"
}
$CommitAuthorName = TruncateString $CommitAuthorName 80
$CommitAuthorEmail = TruncateString $CommitAuthorEmail 80

################################################################################
################################################################################
################################################################################
# Project References
################################################################################
################################################################################
################################################################################

# Check arguments
if($args.Length -ne 6) {
    Write-Warning "BuildVersion: Missing or unknown arguments for project information"
    if($OptionErrorOnArguments) { exit 1 } 
    $ASVersion = "Unknown"
    $UserName = "Unknown"
    $ProjectName = "Unknown"
    $Configuration = "Unknown"
    $BuildMode = "Unknown"
}
else {
    $ASVersion = TruncateString $args[1] 80
    $UserName = TruncateString $args[2] 80
    $ProjectName = TruncateString $args[3] 80
    $Configuration = TruncateString $args[4] 80
    $BuildMode = TruncateString $args[5] 80
    $ProjectMarcos = [Ref]$ASVersion, [Ref]$UserName, [Ref]$ProjectName, [Ref]$Configuration, [Ref]$BuildMode 
    for($i = 0; $i -lt $ProjectMarcos.Length; $i++) {
        if($ProjectMarcos[$i].Value[0] -eq "$") { # Catch incomplete macros which cause warnings and confusion
            $ProjectMarcos[$i].Value = "Unknown"
        }
    }
}

################################################################################
################################################################################
################################################################################
# Output
################################################################################
################################################################################
################################################################################

################
# Initialization
################
$GitInitialization = "URL:='$Url',Branch:='$Branch',Tag:='$Tag',AdditionalCommits:=$AdditionalCommits,Version:='$Version',Sha1:='$Sha1',Describe:='$Describe',UncommittedChanges:='$UncommittedChanges',ChangeWarning:=$ChangeWarning,CommitDate:=DT#$CommitDate,CommitAuthorName:='$CommitAuthorName',CommitAuthorEmail:='$CommitAuthorEmail'"

$ProjectInitialization = "ASVersion:='$ASVersion',UserName:='$UserName',ProjectName:='$ProjectName',Configuration:='$Configuration',BuildMode:='$BuildMode',BuildDate:=DT#$BuildDate"

$BuildVersionInit = "(Git:=($GitInitialization),Project:=($ProjectInitialization))"

###################################
# Check global variable declaration
###################################
$GlobalOption = $False
if([System.IO.File]::Exists($GlobalFile)) {
    $GlobalVariableContent = Get-Content $GlobalFile
    $GlobalVariableMatch = [regex]::Match($GlobalVariableContent, "([a-zA-Z_][a-zA-Z_0-9]+)\s*:\s*$TypeIdentifier\s*(:=[^;]+)?;")
    if($GlobalVariableMatch.Success) {
        $GlobalVariableIdentifier = $GlobalVariableMatch.Groups[1].Value
        Write-Host "BuildVersion: Writing version information to $GlobalVariableIdentifier of type $TypeIdentifier in file $GlobalFile"
        Set-Content -Path $GlobalFile $GlobalVariableContent.Replace($GlobalVariableMatch.Value, "$GlobalVariableIdentifier : $TypeIdentifier := $BuildVersionInit;")
        $GlobalOption = $True 
    }
}

####################################
# Generate Variable Declaration File
####################################

if((-not $GlobalOption) -and (-not $ProgramFound)) {
    Write-Host "BuildVersion: Version information not initialized. Create ST program $ProgramName or declare variable of type $TypeIdentifier in $GlobalDeclarationName"
    if($OptionErrorIfNoInitialization) { exit 1 }
    else { exit 0 }
}

################################################################################
# Local Declaration File
################################################################################

# Read and search text in Variables.var in $ProgramName
if($ProgramFound) {
    # Read
    $File = $ProgramPath + "Variables.var"
    $RelativeFile = $File.Replace($LogicalPath, ".\Logical\")
    if([System.IO.File]::Exists($File)) {
        $Content = Get-Content $File
    }
    else {
        # Force empty read
        $Content = ""
    }
    # Search
    $Regex = @"
(?x)
\(\*This \s file \s was \s automatically \s generated \s by \s ([\w\d\.]+) \s on \s ([\d-:]+)\.\*\) [\s\r\n]+
.+ [\s\r\n]+
.+ [\s\r\n]+
\s* BuildVersion \s* : \s* BuildVersionType \s*
:= \s* \( \s*
Script \s* := \s* \( ( .+ ) \)
\s* , \s*
Git \s* := \s* \( ( .+ ) \)
\s* , \s*
Project \s* := \s* \( ( .+ ) \)
\) \s* ;
"@
    $Match = [regex]::Match($Content, $Regex)
    if($Match.Success) {
        $Content = $Content.Replace($Match.Groups[1].Value, $ScriptName)
        $Content = $Content.Replace($Match.Groups[2].Value, $BuildDate)
        $Content = $Content.Replace($Match.Groups[4].Value, $GitInitialization)
        $Content = $Content.Replace($Match.Groups[5].Value, $ProjectInitialization)
        Set-Content -Path $File $Content
        Write-Host "BuildVersion: $RelativeFile updated with build version information"
    }
    else {
        $Content = @"
(*This file was automatically generated by $ScriptName on $BuildDate.*)
(*Do not modify the contents of this file.*)
VAR
    BuildVersion : BuildVersionType := (Script:=(BuiltWithGit:=FALSE),Git:=($GitInitialization),Project:=($ProjectInitialization)); (* Build version information *)
END_VAR
"@
        Set-Content -Path $File $Content
        Write-Host "BuildVersion: $RelativeFile overwritten with build version information"
    }
}

#############################
# Write configuration version
#############################

# EXPERIMENTAL
# NOTE: Writing to the Hardware.hw causes the build and Automation Studio to hang up for several seconds

# $TagRegex = "\d{1,2}\.\d{1,2}\.\d{1,2}"
# $TagMatch = [regex]::Match($Tag, $TagRegex)
# $TagMatchValue = $TagMatch.Value
# if($TagMatch.Success) {
#     $HardwareFile = $args[0] + "\Physical\" + $args[4] + "\Hardware.hw"
#     if([System.IO.File]::Exists($HardwareFile)) {
#         $HardwareContent = Get-Content $HardwareFile
#         $HardwareVersionMatch = [regex]::Match($HardwareContent, "<Parameter\s*ID=""ConfigVersion""\s*Value=""($TagRegex)""\s*/>")
#         $HardwareIDMatch = [regex]::Match($HardwareContent, "<Parameter\s*ID=""ConfigurationID""\s*Value=""[a-zA-Z_][a-zA-Z_0-9]+""\s*/>")
#         if($HardwareVersionMatch.Success) {
#             if($HardwareVersionMatch.Groups[1].Value -ne $TagMatchValue) {
#                 $NewVersion = $HardwareVersionMatch.Value.Replace($HardwareVersionMatch.Groups[1].Value, $TagMatchValue)
#                 $FileContent = $HardwareContent.Replace($HardwareVersionMatch.Value, $NewVersion)
#                 Write-Host "BuildVersion: Setting configuration version to $TagMatchValue"
#                 # Either option seems to work
#                 # $FileContent | Out-File -FilePath $HardwareFile -Encoding UTF8
#                 # Set-Content -Path $HardwareFile -Encoding UTF8 -Value $FileContent
#             }
#         }
#         elseif($HardwareIDMatch.Success) {
#             $VersionAndIDParameter = $HardwareIDMatch.Value + "`r`n    <Parameter ID=""ConfigVersion"" Value=""$TagMatchValue"" />"
#             $FileContent = $HardwareContent.Replace($HardwareIDMatch.Value, $VersionAndIDParameter)
#             Write-Host "BuildVersion: Adding configuration version $TagMatchValue"
#             # Either option seems to work
#             # $FileContent | Out-File -FilePath $HardwareFile -Encoding UTF8
#             # Set-Content -Path $HardwareFile -Encoding UTF8 -Value $FileContent
#         }
#     }
# }

# Complete
Write-Host "BuildVersion: Completed $ScriptName powershell script"
