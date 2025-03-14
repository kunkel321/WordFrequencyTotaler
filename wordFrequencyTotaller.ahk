#Requires AutoHotkey v2.0
#SingleInstance Force

; Word Frequency Calculator
; This script loads a CSV file with web-occurence word frequencies
; and calculates the total frequency of a provided list of words
; or a hotstring pattern using word-beginning, word-ending, or word-middle patterns.

^+!f::ShowCalculator() ; Show the GUI (Ctrl+Shift+Alt+F)
^!f::CalculateFromList() ; Calculate and append frequency of word list or hotstring in clipboard (Ctrl+Alt+F)

; Global settings
global ERROR_LOG := false
global wordFreqMap := Map()
global EXPECTED_WORD_COUNT := 88916 ; this many lines in freq data csv. 
global DATA_FILE := "unigram_freq_list_filtered_88k.csv"
global IS_DATA_LOADED := false

; ===== MAIN SCRIPT =====
; Initialize the frequency data
InitializeFrequencyData()
Return

; ===== CORE FUNCTIONS =====

; Initialize word frequency data
InitializeFrequencyData() {
    global IS_DATA_LOADED
    
    if (!IS_DATA_LOADED) {
        LogMessage("Starting Word Frequency Calculator")
        result := LoadWordFrequencies(DATA_FILE)
        if (result)
            IS_DATA_LOADED := true
    }
    SoundBeep(820, 350)  ; 820 Hz for 350 ms
    SoundBeep(950, 200)  ; 950 Hz for 200 ms
    return IS_DATA_LOADED
}

; Load word frequencies from CSV file
LoadWordFrequencies(filePath) {
    try {
        ; Clear existing data
        wordFreqMap.Clear()
        
        ; Start timing for performance measurement
        startTime := A_TickCount
        
        ; Read the CSV file
        LogMessage("Reading CSV file: " filePath)
        
        ; Process the file directly from disk, one line at a time
        wordCount := 0
        duplicateCount := 0
        skippedLines := 0
        
        ; Open the file for reading
        file := FileOpen(filePath, "r")
        if (!file) {
            LogError("Could not open file: " filePath)
            return false
        }
        
        ; Read line by line
        while !file.AtEOF {
            line := file.ReadLine()
            
            ; Skip empty lines
            if (line = "" || line = "`r")
                continue
            
            ; Split the line into word and frequency
            commaPos := InStr(line, ",")
            if (commaPos) {
                word := Trim(SubStr(line, 1, commaPos - 1))
                freqStr := Trim(SubStr(line, commaPos + 1))
                
                ; Skip lines with empty frequencies
                if (word = "" || freqStr = "") {
                    skippedLines++
                    LogError("Skipped line with empty word or frequency: " line)
                    continue
                }
                
                ; Convert frequency to number
                freq := Number(freqStr)
                if (freq = 0 && freqStr != "0") {
                    skippedLines++
                    LogError("Skipped line with invalid frequency: " line)
                    continue
                }
                
                ; Convert word to lowercase for consistency
                word := StrLower(word)
                
                ; Check for duplicates
                if (wordFreqMap.Has(word)) {
                    duplicateCount++
                    ; For duplicates, add the frequencies together
                    wordFreqMap[word] += freq
                } else {
                    ; Add new word
                    wordFreqMap[word] := freq
                    wordCount++
                }
            }
        }
        
        ; Close the file
        file.Close()
        
        ; Calculate loading time
        endTime := A_TickCount
        loadTime := (endTime - startTime) / 1000
        
        ; Log loading details
        LogMessage("Loading completed in " loadTime " seconds")
        LogMessage("Unique words loaded: " wordCount)
        LogMessage("Duplicate entries found: " duplicateCount)
        LogMessage("Skipped lines: " skippedLines)
        
        ; Verify against expected count
        if (wordCount + duplicateCount + skippedLines != EXPECTED_WORD_COUNT - 1) { ; -1 because you manually removed one
            LogError("Warning: Total processed entries (" wordCount + duplicateCount + skippedLines ") doesn't match expected count (" EXPECTED_WORD_COUNT - 1 ")")
        }
        
        return true
    }
    catch Error as err {
        LogError("Error loading frequency file: " err.Message)
        MsgBox("Error loading frequency file: " err.Message, "Error")
        return false
    }
}

; Parse a hotstring to extract components
ParseHotstring(hotstring) {
    ; Extract components using regex (handles both regular and function-based hotstrings)
    hsRegex := "(?Jim)^:(?<Opts>[^:]+)*:(?<Trig>[^:]+)::(?:f\((?<Repl>[^,)]*)[^)]*\)|(?<Repl>[^;\v]+))?(?<fCom>\h*;\h*(?:\bFIXES\h*\d+\h*WORDS?\b)?(?:\h;)?\h*(?<mCom>.*))?$" ; Awesome regex by andymbody
    
    if (RegExMatch(hotstring, hsRegex, &match)) {
        ; Log the raw match data for debugging
        LogMessage("Raw regex match - Options: '" match.Opts "', Replacement: '" match.Repl "'")
        
        ; Clean up the replacement text - explicitly remove quotes
        ; In ParseHotstring function, replace:
        cleanReplacement := StrReplace(match.Repl, '"', '')
        cleanReplacement := StrReplace(cleanReplacement, '”', '')
        LogMessage("Cleaned replacement: '" cleanReplacement "'")
        
        result := {
            options: StrReplace(match.Opts, 'B0X', ''),
            ;trigger: match.Trig,
            replacement: cleanReplacement,
            comment: match.mCom
        }
        
        ; Determine the type of hotstring based on options
        result.isBeginning := InStr(result.options, "*") && !InStr(result.options, "?")
        result.isEnding := !InStr(result.options, "*") && InStr(result.options, "?")
        result.isMiddle := InStr(result.options, "*") && InStr(result.options, "?")
        
        return result
    }
    return false
}

; Find words matching a hotstring pattern
FindMatchingWords(hsInfo) {
    matches := []
    lcReplacement := StrLower(hsInfo.replacement)
    
    if (!lcReplacement)
        return matches
    
    ; Determine type for logging
    typeStr := ""
    if (hsInfo.isMiddle)
        typeStr := "Word-Middle"
    else if (hsInfo.isBeginning)
        typeStr := "Word-Beginning"
    else if (hsInfo.isEnding)
        typeStr := "Word-Ending"
    else
        typeStr := "Regular"
    
    LogMessage("Finding matches for '" lcReplacement "' - Type: " typeStr)
    
    ; Debug log the matching criteria
    if (hsInfo.isEnding)
        LogMessage("Word-Ending pattern: Looking for words ENDING with '" lcReplacement "'")
    
    ; Iterate through the word frequency map to find matches
    for word, freq in wordFreqMap {
        ; Skip processing if word is empty
        if (word = "")
            continue
            
        if (hsInfo.isMiddle && InStr(word, lcReplacement)) {
            matches.Push(word)
        } else if (hsInfo.isBeginning && SubStr(word, 1, StrLen(lcReplacement)) = lcReplacement) {
            matches.Push(word)
        } else if (hsInfo.isEnding) {
            ; Debug specific case to see why it's not matching
            if (word = "sought" && lcReplacement = "sought")
                LogMessage("Special debug - Word: 'sought', Length: " StrLen(word) ", Replacement: '" lcReplacement "', Length: " StrLen(lcReplacement))
            
            ; Check if the word ends with the replacement
            wordLength := StrLen(word)
            replLength := StrLen(lcReplacement)
            
            if (wordLength >= replLength) {
                endPortion := SubStr(word, wordLength - replLength + 1)
                if (endPortion = lcReplacement) {
                    matches.Push(word)
                    LogMessage("Found ending match: '" word "' ends with '" lcReplacement "'")
                }
            }
        } else if (!hsInfo.isBeginning && !hsInfo.isEnding && !hsInfo.isMiddle && word = lcReplacement) {
            matches.Push(word)
        }
    }
    
    LogMessage("Found " matches.Length " matching words for '" lcReplacement "'")
    return matches
}

CalculateFromList(*)
{    
    ; Ensure we have the clipboard content
    clipText := A_Clipboard
    
    ; Skip if empty
    if (clipText = "") {
        Msgbox("Nothing on clipboard.`n`nCopy a list of words or a hotstring and try again.")
        return
    }
    
    global IS_DATA_LOADED
    if (!IS_DATA_LOADED) {
        MsgBox("Loading frequency data. This may take a moment.", "Word Frequency Calculator")
        if (!InitializeFrequencyData()) {
            MsgBox("Failed to load word frequency data. Please check the CSV file.", "Word Frequency Calculator")
            return
        }
        SoundBeep(750, 500)  ; 750 Hz for 500 ms
    }

    ; Check if input is a hotstring
    isHotstring := RegExMatch(Trim(clipText), "^:[^:]+:[^:]+::")
    
    ; Process based on input type
    if (isHotstring) {
        result := CalculateHotstringFrequency(clipText)
    } else {
        result := CalculateWordFrequency(clipText)
    }
    
    ; Log details for debugging
    LogMessage("Clipboard calculation - Total frequency: " result.total)
    LogMessage("Clipboard calculation - Words found: " result.found.Count)
    LogMessage("Clipboard calculation - Words not found: " result.notFound.Length)
    
    ; Format the result and append to clipboard
    if (result.total > 0) {
        ; Calculate and format in millions with 2 decimal places
        formattedTotal := Format("{:.2f}", result.total / 1000000)

        ; Set the frequency result to clipboard
        A_Clipboard := "Frequency: " formattedTotal " million"
        
        ; Show a tooltip to confirm
        ToolTip("Frequency calculated: " formattedTotal " million")
        SetTimer(HideTooltip, -2000)  ; Hide after 2 seconds
    }
    else {
        ; No frequency data found
        A_Clipboard := "Frequency: 0 (no matches found)"
        
        ; Show a tooltip to indicate no matches
        ToolTip("No frequency data found")
        SetTimer(HideTooltip, -2000)  ; Hide after 2 seconds
    }
}

; Hide tooltip function for timer
HideTooltip() {
    ToolTip()
}

; Calculate frequency for a hotstring
CalculateHotstringFrequency(hotstringText) {
    global IS_DATA_LOADED
    
    ; Ensure data is loaded
    if (!IS_DATA_LOADED) {
        if (!InitializeFrequencyData()) {
            LogError("Failed to initialize frequency data for calculation")
            return {total: 0, found: Map(), notFound: []}
        }
    }
    
    ; Log the raw hotstring text for debugging
    LogMessage("Processing hotstring: '" hotstringText "'")
    
    ; Parse the hotstring
    hsInfo := ParseHotstring(hotstringText)
    if (!hsInfo) {
        LogError("Failed to parse hotstring: " hotstringText)
        return {total: 0, found: Map(), notFound: [hotstringText]}
    }
    
    ; Double-check the replacement doesn't have any remaining quotes
    if (InStr(hsInfo.replacement, '"')) {
        LogMessage("Warning: Quotes still present in replacement after parsing. Removing them again.")
        hsInfo.replacement := StrReplace(hsInfo.replacement, '"', '')
    }
    
    ; Find matching words
    matchingWords := FindMatchingWords(hsInfo)
    
    ; Calculate total frequency
    totalFreq := 0
    foundWords := Map()
    notFoundWords := []
    
    for idx, word in matchingWords {
        freq := wordFreqMap[word]
        totalFreq += freq
        foundWords[word] := freq
    }
    
    ; If no matches were found, add the replacement to notFoundWords
    if (matchingWords.Length = 0)
        notFoundWords.Push(hsInfo.replacement)
    
    ; Log results
    LogMessage("Hotstring frequency calculation for '" hsInfo.replacement "' - Total: " totalFreq)
    LogMessage("Matching words: " matchingWords.Length)
    
    return {total: totalFreq, found: foundWords, notFound: notFoundWords}
}

; Calculate total frequency for a list of words
; This is the main function that can be called from other scripts
CalculateWordFrequency(wordList) {
    global IS_DATA_LOADED
    
    ; Ensure data is loaded
    if (!IS_DATA_LOADED) {
        if (!InitializeFrequencyData()) {
            LogError("Failed to initialize frequency data for calculation")
            return {total: 0, found: Map(), notFound: []}
        }
    }
    
    ; Always start with fresh objects to prevent accumulation from previous calls
    totalFreq := 0
    foundWords := Map()
    notFoundWords := []
    
    ; Handle empty input
    if (wordList = "") {
        return {total: 0, found: foundWords, notFound: notFoundWords}
    }
    
    ; Replace all newlines, tabs and multiple spaces with single spaces
    cleanInput := RegExReplace(wordList, "[\r\n\t,]+", " ")
    cleanInput := RegExReplace(cleanInput, " +", " ")
    cleanInput := Trim(cleanInput)
    
    ; Split input text into words
    words := StrSplit(cleanInput, A_Space)
    
    ; Process each word
    Loop words.Length {
        word := words[A_Index]
        
        ; Clean the word (remove punctuation, etc.)
        cleanWord := RegExReplace(Trim(word), "[^\w]", "")
        
        ; Skip empty words
        if (cleanWord = "")
            continue
        
        ; Convert to lowercase for case-insensitive comparison
        cleanWord := StrLower(cleanWord)
        
        ; Look up the word in the frequency map
        if (wordFreqMap.Has(cleanWord)) {
            freq := wordFreqMap[cleanWord]
            totalFreq += freq
            
            ; Track found words and their frequencies
            foundWords[cleanWord] := freq
        }
        else {
            ; Track words not found in the database
            notFoundWords.Push(cleanWord)
        }
    }
    
    ; Return a new result object each time
    return {total: totalFreq, found: foundWords, notFound: notFoundWords}
}

; ===== GUI FUNCTIONS =====

; Show or activate the calculator GUI
ShowCalculator() {
    global IS_DATA_LOADED
    
    if (!IS_DATA_LOADED) {
        MsgBox("Loading frequency data. This may take a moment.", "Word Frequency Calculator")
        if (!InitializeFrequencyData()) {
            MsgBox("Failed to load word frequency data. Please check the CSV file.", "Word Frequency Calculator")
            return
        }
        SoundBeep(750, 500)  ; 750 Hz for 500 ms
    }
    
    if !IsSet(mainGui) || !WinExist("ahk_id " mainGui.Hwnd) {
        CreateGUI()
    } else {
        WinActivate("ahk_id " mainGui.Hwnd)
    }
}

; Create the GUI
CreateGUI() {
    ; Create main window
    mainGui := Gui("AlwaysOnTop", "Word Frequency Calculator")
    mainGui.SetFont("s10")
    
    ; Add controls
    mainGui.AddText("xm y10 w240", "Enter words or a hotstring pattern")
       
    ; Add named controls with the v option for easy identification
    mainGui.Add("Edit", "xm y30 w500 r4 vInputField")
    mainGui.Add("Button", "xm y110 w220", "Calculate Frequency").OnEvent("Click", CalculateButtonHandler)
    mainGui.Add("Text", "xm y150 w500 vResultText", "Total frequency: 0")
    mainGui.Add("ListView", "xm y180 w500 r10 vDetailsList", ["Word", "Frequency"])
    mainGui["DetailsList"].ModifyCol(1, 200)
    mainGui["DetailsList"].ModifyCol(2, 150)
    mainGui.Add("Text", "xm y390 w500 vNotFoundText", "Words not found: None")
    
    ; Add hotkey information
    mainGui.AddText("xm y410 w500", "Press Ctrl+Alt+F to show this calculator anytime")
    mainGui.AddText("xm y430 w500", "Press Ctrl+Shift+Alt+F to calculate from clipboard")
    
    ; Show the GUI
    mainGui.Show()
}

; Separate handler function for calculate button
CalculateButtonHandler(ctrl, *) {
    mainGui := ctrl.Gui
    
    ; Access controls by their variable names
    eInput := mainGui["InputField"]
    txtResult := mainGui["ResultText"]
    lvDetails := mainGui["DetailsList"]
    txtNotFound := mainGui["NotFoundText"]
    
    ; Verify all controls were found before proceeding
    if (!(IsSet(eInput) && IsSet(txtResult) && IsSet(lvDetails) && IsSet(txtNotFound))) {
        MsgBox("Error: Could not find all required controls. Check your GUI code.")
        return
    }
    
    CalculateFreqGUI(mainGui, eInput, txtResult, lvDetails, txtNotFound)
}

; Calculate frequency function for GUI
CalculateFreqGUI(mainGui, eInput, txtResult, lvDetails, txtNotFound) {
    ; Get input text
    inputText := eInput.Value
    
    ; Log the input
    LogMessage("Processing input: " inputText)
    
    ; Calculate frequency - check if it's a hotstring or word list
    startTime := A_TickCount
    
    ; Check if input is a hotstring
    isHotstring := RegExMatch(Trim(inputText), "^:[^:]+:[^:]+::")
    
    ; Process based on input type
    if (isHotstring) {
        result := CalculateHotstringFrequency(inputText)
    } else {
        result := CalculateWordFrequency(inputText)
    }
    
    calcTime := (A_TickCount - startTime) / 1000
    
    ; Log calculation time and results
    LogMessage("Calculation completed in " calcTime " seconds")
    LogMessage("Total frequency: " result.total)
    LogMessage("Found words: " result.found.Count)
    LogMessage("Not found words: " result.notFound.Length)
    
    ; Update result display
    txtResult.Value := "Web frequency " FormatNumber(result.total) "m"
    
    ; Clear the list
    lvDetails.Delete()
    
    ; Populate found words and their frequencies
    for word, freq in result.found {
        lvDetails.Add(, word, FormatNumber(freq))
    }
    
    ; Show words not found
    if (result.notFound.Length > 0) {
        txtNotFound.Value := "Words not found: " result.notFound.Length " words (" StrJoin(result.notFound, ", ") ")"
    }
    else {
        txtNotFound.Value := "Words not found: None"
    }
}

; ===== UTILITY FUNCTIONS =====

; Format number with thousand separators
FormatNumber(num) {
    return Format("{:.2f}", num/1000000)
}

; Join array elements into a string
StrJoin(arr, delimiter) {
    result := ""
    
    Loop arr.Length {
        if (A_Index > 1)
            result .= delimiter
        result .= arr[A_Index]
    }
    
    return result
}

; Log error messages to file
LogError(message) {
    if (ERROR_LOG) {
        FileAppend(FormatTime(A_Now, "MMM-dd hh:mm:ss") ": ERROR - " message "`n", "word_freq_error_log.txt")
    }
}

; Reduce logging of duplicates to improve performance
LogMessage(message) {
    if (ERROR_LOG) {
        ; Skip logging individual duplicates to reduce file I/O
        if (SubStr(message, 1, 15) != "Duplicate word ")
            FileAppend(FormatTime(A_Now, "MMM-dd hh:mm:ss") ": INFO - " message "`n", "word_freq_error_log.txt")
    }
}