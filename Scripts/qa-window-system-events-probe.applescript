on run argv
    tell application "System Events"
        if not (exists process "ZoidCoachQA") then
            return "SETUP_FAIL|process=absent|window=unknown|descendants=unknown"
        end if
        tell process "ZoidCoachQA"
            if not (exists window 1) then
                return "SETUP_FAIL|process=present|window=absent|descendants=unknown"
            end if
            tell window 1
                set windowName to name
                set windowPosition to position
                set windowSize to size
                set isMinimized to value of attribute "AXMinimized"
                set descendantCount to count of entire contents
            end tell
        end tell
    end tell

    set windowWidth to item 1 of windowSize
    set windowHeight to item 2 of windowSize
    if isMinimized is false and windowWidth is 1180 and windowHeight is 760 and descendantCount is 0 then
        return "RED|process=present|window=present|name=" & windowName & "|position=" & (item 1 of windowPosition) & "," & (item 2 of windowPosition) & "|size=1180x760|minimized=false|descendants=0"
    end if
    if isMinimized or windowWidth is not 1180 or windowHeight is not 760 then
        return "SETUP_FAIL|process=present|window=present|name=" & windowName & "|position=" & (item 1 of windowPosition) & "," & (item 2 of windowPosition) & "|size=" & windowWidth & "x" & windowHeight & "|minimized=" & isMinimized & "|descendants=" & descendantCount
    end if
    return "GREEN|process=present|window=present|name=" & windowName & "|position=" & (item 1 of windowPosition) & "," & (item 2 of windowPosition) & "|size=1180x760|minimized=false|descendants=" & descendantCount
end run
