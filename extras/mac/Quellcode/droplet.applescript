property appTitle : "Comics zu CBZ"

on run
	set picked to choose file with prompt "CBR-, PDF- oder EPUB-Dateien waehlen (oder Dateien/Ordner direkt auf das App-Symbol ziehen):" with multiple selections allowed
	open picked
end run

on open theItems
	set q to ""
	repeat with i in theItems
		set q to q & " " & quoted form of POSIX path of i
	end repeat
	set res to POSIX path of (path to resource "cbz.py")
	set cmd to "export PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH; PY=/usr/bin/python3; [ -x \"$PY\" ] || PY=$(command -v python3); \"$PY\" " & quoted form of res & q & " 2>&1"
	try
		set outText to do shell script cmd
		set outText to outText & ""
	on error errMsg
		set outText to errMsg
	end try
	set AppleScript's text item delimiters to linefeed
	set ls to paragraphs of outText
	if (count of ls) > 18 then set ls to items -18 thru -1 of ls
	display dialog (ls as text) buttons {"OK"} default button 1 with title appTitle
end open
