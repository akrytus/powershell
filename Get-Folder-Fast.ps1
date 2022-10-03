<# 
NTFS Folder Permissions
Author: Aaron Krytus
Date: 9/12/22
Version: 1.0 (9/12/22) - Get NTFS permissions for a root folder recursively

Notes:
    • Ignores the following Users/Accounts:
        ○ BUILTIN (Local accounts)
        ○ S-* (Unidentified accounts)
        ○ CREATOR (This permission is always full control)
        ○ NT AUTHORITY (System accounts)
    
    • Excel Formatting (recommended):
		○ Open .csv file
		○ Save As "Excel Workbook"
		○ Create table including all data (Format Table->Second table down(1x2)->A1->Last Cell)
        ○ Freeze Panes (View->Freeze Panes->Top Row)
#>


#Functions
#===========================
function Check-IsElevated {
    #Check if PowerShell is runninng as Administrator
    $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object System.Security.Principal.WindowsPrincipal($id)
    if ($p.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)){
       Write-Host "Script running as Admin" -ForegroundColor Green
    }      
    else{
        Write-Host "Not running with elevated permissions!" -ForegroundColor Red
        $flag = "True"}
    Return $flag
 }

function Get-NTFS-ACL {
    #Edit These Variables
    $RootPath = "E:\Shared"
    $LogPath = "C:\Temp"
    $OutputPath = "C:\Temp"


    #Variables
    $start = Get-Date
    $Error.clear
    $fnDateFormat = 'MMddyy' #Date format for Files
    $dtFormat = "dd-MMM-yyyy HH:mm:ss" #Date format for logs
    $OutFile = "$OutputPath\ACL-Permissions-$(Get-Date -Format $fnDateFormat).csv"
    $logs = "$LogPath\ACL-Permissions-$(Get-Date -Format $fnDateFormat).log"
    $Output = @()     #Create Object Table for CSV Output
   

    #Update Log file
    Add-Content $logs -value "`n`n"
    Add-Content $logs -value "-------------------------------------------------"
    Add-Content $logs -value "$(Get-Date -Format $dtFormat)     Starting Script"

    #Verify or Create Folders
        #Log Folder
        try{
            if(!(Get-Item -Path "$LogPath" -ErrorAction SilentlyContinue)){ #Verify if the folder exists before creating it
                New-Item -Path $LogPath -ItemType "directory" #Folder DNE, create it
                Add-Content $logs -value "$(Get-Date -Format $dtFormat)     Creating Log folder: $LogPath"
            } 
            else {Add-Content $logs -value "$(Get-Date -Format $dtFormat)     Log Folder $LogPath already exists"} #Folder already exists
             
        }
        catch{ #Error creating folder
            Add-Content $logs -value "$(Get-Date -Format $dtFormat)     Creating folder $LogPath FAILED!!!"
            $Error | Out-File $logs -Append
        }

        #Output Folder
        try{
            if(!(Get-Item -Path "$OutputPath" -ErrorAction SilentlyContinue)){ #Verify if the folder exists before creating it
                New-Item -Path $OutputPath -ItemType "directory" #Folder DNE, create it
                Add-Content $logs -value "$(Get-Date -Format $dtFormat)     Creating Output folder: $OutputPath"
            } 
            else {Add-Content $logs -value "$(Get-Date -Format $dtFormat)     Output Folder $OutputPath already exists"} #Folder already exists
             
        }
        catch{ #Error creating folder
            Add-Content $logs -value "$(Get-Date -Format $dtFormat)     Creating folder $OutPath FAILED!!!"
            $Error | Out-File $logs -Append
        }


       
    #Collect Folders
        #Update screen and logs
        Write-Host "`n`n`n`n`n`nDepending on the number of folders,`nThis may take several minutes..." -ForegroundColor Gray
        Add-Content $logs -value "$(Get-Date -Format $dtFormat)     Collecting folders..."
        
        #Collect Folders
        $Folders = Get-ChildItem -Directory -Path $RootPath -Recurse -Force -ErrorAction SilentlyContinue
    
    
    #Estimates - Calculate
    $FolderCount = $Folders.Count #Required to add logging below
    $estimatedTime = [Math]::Floor($FolderCount / 180) #Round down - Last run avg was 180 folders per minute
    if($estimatedTime -gt 60){$estimatedTime = [Math]::Round($estimatedTime/60,2); $timeFormat = " Hours"}
    else {$timeFormat = " Minutes"} #Display number of minutes
    if($estimatedTime -gt 24){$estimatedTime = [Math]::Round($estimatedTime/24,2); $timeFormat = " Days"}
    
    
    #Update Screen and Logs with estimated time
    Write-Host "`n`nFound " -NoNewLine; Write-Host $Folders.count -ForegroundColor Yellow -NoNewline; Write-Host " folders."
    Add-Content $logs -value "$(Get-Date -Format $dtFormat)     Found $FolderCount folders"
    Write-Host "Estimated time to complete: " -NoNewLine; Write-Host $estimatedTime -ForegroundColor Yellow -NoNewline; Write-Host $timeFormat
    Add-Content $logs -value "$(Get-Date -Format $dtFormat)     Estimated time to complete: $estimatedTime $timeFormat"
    Write-Host "`n`n`n`n`n`nCollecting ACLs..." -ForegroundColor Gray
    Add-Content $logs -value "$(Get-Date -Format $dtFormat)     Collecting ACLs..."
    
    
    #Start Timers and counters
    $starttimer = Get-Date #Start 15 minute timer for Logging
               
    
    #Collect ACLs - Create and start Job to collect ACLs in seperate runspace
        foreach($Folder in $Folders) {
            #Collect Folder ACL
            $Acl = Get-Acl -Path $Folder.FullName -ErrorAction SilentlyContinue
    
            #Owner (Parent)
            if($Acl.Owner -like "O:S-1*"){$AclOwner = "**User Does Not Exist"} #Removes O:S-1 (Unidentified) owners
            else {$AclOwner = $Acl.Owner} #Owner is valid, assign it
            $Properties = [ordered]@{`
                'Folder Name' = $Folder.FullName;
                'Owner' = $AclOwner; #Reassigned from the if statement above
                'Group/User' = $Acl.Group;
                'Permissions' = 'Owner';
                'Inherited' = '';}
            $Output += New-Object -TypeName PSObject -Property $Properties
    
            #Goups/Users Permissions (Child)
            Foreach ($Access in $Acl.Access) {
                #Individual ACLs - Exluding Builtin\NTAuthority\Unidentified etc
                if(($Access.IdentityReference -like "BUILTIN*") -or`
                    ($Access.IdentityReference -like "NT AUTH*") -or`
                    ($Access.IdentityReference -like "CREATOR*") -or`
                    ($Access.IdentityReference -like "*S-1*")) {break}
                else {
                     $Properties = [ordered]@{`
                        'Folder Name' = '     -' + $Folder.FullName; #Indent this to show it belongs to the parent folder for readability 
                        'Owner' = '';
                        'Group/User' = $Access.IdentityReference;
                        'Permissions' = $Access.FileSystemRights;
                        'Inherited' = $Access.IsInherited;}
                     $Output += New-Object -TypeName PSObject -Property $Properties            
                }
            } 
        }
   
    #Output results to CSV
    $Output | Export-Csv $OutFile -NoTypeInformation

    #Finished
    $end = Get-Date
    $runtime = $end - $start
    Add-Content $logs -value "$(Get-Date -Format $dtFormat)     Output file located at $OutFile"
    Add-Content $logs -value "$(Get-Date -Format $dtFormat)     Script has COMPLETED!!!"
    Add-Content $logs -value "$(Get-Date -Format $dtFormat)     Total run time: $runtime"
    Write-Host "`n`nScript has completed!" -ForegroundColor Green
    Write-Host "File: "-NoNewLine 
    Write-Host $Outfile -ForegroundColor Yellow
    Write-Host "Logs: " -NoNewline
    Write-Host $logs
    Write-Host "`n`nRuntime: $runtime"
}


#Start Script
#===========================
Clear-Host
if(Check-IsElevated) {Write-Host "`nPlease re-run as an " -NoNewline; Write-Host "Administrator" -ForegroundColor Yellow; exit}
Get-NTFS-ACL
