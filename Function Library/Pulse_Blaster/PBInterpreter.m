function [interpreted_sequence] = PBInterpreter
%Interprets desired pulse sequence for actual use. This is designed to be
%used within the PBFinalize function

%Adjusts the sequence present in intseq to the
%hardware-friendly form.

%Note: this code is used to adjust a 'natural' pulse sequence to work with
%the hardware as designed. It essentially splits each command that has an
%active SPC into 3 parts: the initial trigger, the wait time while
%collection is ongoing, then a final trigger to signal the end of
%collection

%Instrument dependencies:
%Pulse blaster

%Code dependencies:
%PBInitialization
%InitializationCheck

%PBInterpreter v1.0 5/31/22

global master %#ok<GVMIS>

InitializationCheck('PB')


%For each section (described below), go step by step through the sequence
%to make sure both rules (described below) are followed. Apply the rules
%sequentially.

%Create sections in descending order of size based on loop locations. Begin
%with overall sequence, then move to bigger loop, then its nested loop etc.
%Each section is treated to the same process. For the loop sections, add
%relevant information acting as if the beginning of the loop is just a
%continuation of the end of the loop.

%1. If there is a change in voltage between the current and next instance
%where the counter is on, check the time in between the current and the
%change in voltage. If that time is less than 820 ns, add an extra pulse
%directly after the current, but outside any loops if the issue is not within
%the loop, that matches the voltage and brings duration between the two to
%820 ns.

%2. If there is a change in voltage from the previous to the current and the
%current counter is on, add a 20 ns pulse based on the previous that
%matches the voltage of the current. Subtract 20 ns from the previous to
%compensate for additional time.

%Copies the current sequence then adds a tag that will be used as an
%identifier later. the tag is just the order it comes in
natSeq = master.PB.sequence;

tagCell = num2cell(1:numel(natSeq));
[natSeq.tag] = tagCell{:};
totalSeq = natSeq;%Total sequence is set to original sequence

if master.NIDAQ.confocal
    %Variable creation
    loopTracker = [0 0 0];
    master.PB.sequenceDuration = 0;

    numCycles = 0;%Number of cycles the while loop has run
    endWhile = false;
    while true

        %Creates an array that tracks all the loops. goes through each
        %instruction in the current total sequence to find end loop commands.
        %once found, the start of the loop is found by comparing contextinfo to
        %the tags from the natural sequence. the matrix's columns are as
        %follows: beginning of loop, end of loop, and whether the loop has been
        %analyzed yet.
        nn = 2;
        for ii = 1: length(totalSeq)
            if strcmp(totalSeq(ii).direction,"END_LOOP")
                if numCycles == 0
                    tf = 0;
                else
                    tf = loopTracker(nn,3);
                end
                begLoop = find([totalSeq.tag] == totalSeq(ii).contextinfo);
                currloop = [begLoop ii tf];
                if isfield(master,'debugging') && isfield(master.debugging,'switch') && master.debugging.switch
                    master.debugging.currloop = currloop;
                    master.debugging.loopTracker = loopTracker;
                    master.debugging.ii = ii;
                    master.debugging.tf = tf;
                    master.debugging.begLoop = begLoop;
                end
                loopTracker(nn,:) = currloop;
                nn = nn+1;
            end
        end


        if numCycles == 0 %First analysis cycle
            currentSeq = natSeq;%Snip is entire natural sequence

            loopTracker(1,3) = 1;%Mark natural sequence as completed
            parentLoop = [1 numel(totalSeq)];%Records this loop as the size of the natural sequence
            recombiner = [];%Nothing is outside the current sequence

        else

            %Finds the next loop to analyze
            while true
                %Find where there are end loop commands between the current beginning
                %and the current end
                if ~isempty(parentLoop)
                    endLocs = [ismember(loopTracker(:,2),parentLoop(end,1):parentLoop(end,2)) loopTracker(:,3) == 0];
                    endLocs = find(all(endLocs,2));
                else
                    endLocs = [ismember(loopTracker(:,2),1:numel(totalSeq)) loopTracker(:,3) == 0];
                    endLocs = find(all(endLocs,2));
                end

                if isempty(endLocs) %No loops to analyze within current

                    %If you can still "zoom out" into the parent loop, do so.
                    %Otherwise, the entire interpreter is finished
                    if ~isempty(parentLoop)
                        parentLoop(end,:) = [];
                    else
                        endWhile = true;
                        break
                    end

                else %There are loops to do within the current
                    loopTracker(endLocs(end),3) = 1;%Will analyze the last possible loop
                    break
                end

            end

            %Ends entire interpreter
            if endWhile
                break
            end

            %Assign current sequence as the last new end loop command location
            parentLoop(end+1,:) = [loopTracker(endLocs(end),1) loopTracker(endLocs(end),2)]; %#ok<AGROW>
            currentSeq = totalSeq(parentLoop(end,1)+1:parentLoop(end,2));

            %Excluded parts of sequence that will be recombined with the current
            %sequence at the end
            recombiner = totalSeq;
            recombiner(parentLoop(end,1)+1:parentLoop(end,2)) = [];

        end

        %Makes list of where the counter is on, where the voltage is on, and
        %what the cumulative duration up to that point is for each pulse
        ctrList = zeros(length(currentSeq),1);
        voltList = ctrList;
        cumDur = zeros(length(currentSeq),1);
        for ii = 1:length(currentSeq)
            binOut = PBDec2Bin(currentSeq(ii).output);
            ctrList(ii) = str2double(binOut(end-1));
            voltList(ii) = str2double(binOut(end-2));
            if ii ~= 1
                cumDur(ii) = cumDur(ii-1) + currentSeq(ii-1).duration;
            end
        end

        ctrLocs = find(ctrList);%Location of where counter is on

        if ~isempty(ctrLocs)

            %If this isn't the natural sequence,
            if numCycles ~= 0
                ctrLocs(end+1) = numel(currentSeq) + ctrLocs(1); %#ok<AGROW>
                voltList(end+1:end+ctrLocs(1)) = voltList(1:ctrLocs(1));
                cumDur(end+1:end+ctrLocs(1)) = cumDur(1:ctrLocs(1)) + cumDur(end);
            end

            %Rule 1
            for ii = 1:numel(ctrLocs)-1
                n = ctrLocs(ii);
                m = ctrLocs(ii+1);
                if any(voltList(n) ~= voltList(n+1:m))
                    firstChange = find(voltList(n+1:m) ~= voltList(n));
                    firstChange = firstChange(1)+n;
                    durDiff = cumDur(firstChange) - cumDur(n+1);
                    

                    if durDiff < 800
                        %find a good location to insert the extra duration
                        durAdd = 820 - durDiff;
                        jj = n+1;
                        while true
                            if jj  > numel(currentSeq)
                                jj = jj-1;
                                break
                            end
                            loc(1) = strcmp(currentSeq(jj).direction,'LOOP');
                            loc(2) = strcmp(currentSeq(jj).direction,'END_LOOP');
                            if ~loc(2) || voltList(jj) ~= voltList(n) || loc(1)
                                break
                            end
                            jj = jj+1;
                        end


                        newPulse = currentSeq(jj);
                        newPulse.direction = 'CONTINUE';
                        newPulse.duration = durAdd;
%                         newPulse.output = newPulse.output - 2;
                        newPulse.binaryoutput(end-1) = '0';
                        newPulse.tag = newPulse.tag - .9;%Add directly after chosen pulse

                        if voltList(jj) ~= voltList(n)
                            if voltList(n)
                                newPulse.output = newPulse.output + 4;
                                newPulse.binaryoutput(end-2) = '1';
                            else
                                newPulse.output = newPulse.output - 4;
                                newPulse.binaryoutput(end-2) = '0';
                            end
                        end

                        currentSeq(end+1) = newPulse; %#ok<AGROW>

                    end

                end

            end

            [~,idx]=sort([currentSeq.tag]);
            currentSeq = currentSeq(idx);

            ctrList = zeros(length(currentSeq),1);
            voltList = ctrList;
            cumDur = zeros(length(currentSeq),1);
            for ii = 1:length(currentSeq)
                
                binOut = PBDec2Bin(currentSeq(ii).output);
                ctrList(ii) = str2double(binOut(end-1));
                voltList(ii) = str2double(binOut(end-2));
                if ii ~= 1
                    cumDur(ii) = cumDur(ii-1) + currentSeq(ii-1).duration;
                end
            end

            ctrLocs = find(ctrList);

            if numCycles ~= 0
                ctrLocs(end+1) = numel(currentSeq) + ctrLocs(1); %#ok<AGROW>
                %       ctrList(end+1:end+ctrLocs(1)) = ctrList(1:ctrLocs(1));
                voltList(end+1:end+ctrLocs(1)) = voltList(1:ctrLocs(1));
                %       cumDur(end+1:end+ctrLocs(1)) = cumDur(1:ctrLocs(1)) + cumDur(end);
            end

            %Rule 2
            for ii = 1:numel(ctrLocs)
                n = ctrLocs(ii);
                addNew = false;

                %First pulse
                if n == 1

                    if numCycles == 0
                        newPulse = currentSeq(1);
                        if voltList(1)
                            newPulse.output = 4;
                        else
                            newPulse.output = 0;
                        end
                        newPulse.binaryoutput = PBDec2Bin(newPulse.output);
                        addNew = true;

                    else
                        if voltList(1) ~= voltList(numel(currentSeq))
                            addNew = true;

                            newPulse = currentSeq(end);
                            newPulse.tag = currentSeq(1).tag;

                            currentSeq(end).duration = currentSeq(end).duration - 20;

                            if voltList(n)
                                newPulse.output = newPulse.output + 4;
                                newPulse.binaryoutput(end-2) = '1';
                            else
                                newPulse.output = newPulse.output - 4;
                                newPulse.binaryoutput(end-2) = '0';
                            end

                        end

                    end

                    %Not first pulse
                elseif voltList(n) ~= voltList(n-1)

                    if strcmp(currentSeq(n-1).direction,'LOOP')
                        endLoop = find([currentSeq.contextinfo] == currentSeq(n-1).tag);
                        if ~isscalar(endLoop)
                            endLoop = find(strcmp(currentSeq(endLoop).direction,'END_LOOP'));
                        end
                        currentSeq(endLoop).duration = currentSeq(endLoop).duration - 20;
                    else
                        currentSeq(n-1).duration = currentSeq(n-1).duration - 20;
                    end

                    addNew = true;
                    newPulse = currentSeq(n-1);
                    newPulse.tag = currentSeq(n).tag;



                    if voltList(n)
                        newPulse.output = newPulse.output + 4;
                        newPulse.binaryoutput(end-2) = '1';
                    else
                        newPulse.output = newPulse.output - 4;
                        newPulse.binaryoutput(end-2) = '0';
                    end

                end

                if addNew
                    newPulse.direction = 'CONTINUE';
                    newPulse.duration = 20;
                    newPulse.tag = newPulse.tag - .1;
                    currentSeq(end+1) = newPulse; %#ok<AGROW>



                end



            end

        end

        if isempty(recombiner)
            recombiner = currentSeq;
        else
            recombiner(end+1:end+numel(currentSeq)) = currentSeq;
        end
        [~,idx]=sort([recombiner.tag]);
        totalSeq = recombiner(idx);

        numCycles = numCycles + 1;


    end
end

    newPulse.duration = 20;
    newPulse.output = 0;
    newPulse.binaryoutput = PBDec2Bin(0);
    newPulse.tag = 0;
    if isfield(totalSeq,'description')
      newPulse.description = '';
    end

    if master.PB.addTotalLoops
        totalSeq(2:end+1) = totalSeq;
        newPulse.direction = 'LOOP';
        newPulse.contextinfo = master.PB.totalLoops;
        totalSeq(1) = newPulse;

        newPulse.tag = numel(natSeq) + 1;
        newPulse.direction = 'END_LOOP';
        newPulse.contextinfo = 0;
        totalSeq(end+1) = newPulse;
    end

    for ii = 1:numel(totalSeq)
        endYN = strcmp(totalSeq(ii).direction,'END_LOOP');
        if endYN
            begLoop = find([totalSeq.tag] == totalSeq(ii).contextinfo);
            totalSeq(ii).contextinfo = begLoop;
        end
    end

    totalSeq = rmfield(totalSeq,'tag');
    newPulse = rmfield(newPulse,'tag');

    newPulse.direction = 'CONTINUE';
    newPulse.contextinfo = 0;

    totalSeq(end+1) = newPulse;

    newPulse.direction = 'STOP';

    totalSeq(end+1) = newPulse;

    interpreted_sequence = totalSeq;
end


