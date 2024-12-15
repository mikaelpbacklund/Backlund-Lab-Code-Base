classdef pulse_blaster < instrumentType

   %Use modifyPulse if you wish to change something about the pulse
   %sequence as that will perform the necessary adjustments. Without this,
   %the sequence does not update properly and desyncs can happen

   properties
      useTotalLoop%Encompass the entire sequence in a loop
      nTotalLoops%How many loops the above should run for
      sendUponAddition%Send sequence to pulse blaster when running addPulse
   end

   properties (SetAccess = {?pulse_blaster ?instrumentType ?experiment}, GetAccess = public)
      %Read-only for user, derived from config or functions     
      commands
      clockSpeed%MHz
      formalChannelNames
      acceptableChannelNames
      formalDirectionNames
      acceptableDirectionNames
      units
      plots
      adjustedSequence
      sequenceSentToPulseBlaster%The last recorded sequence sent to the pulse blaster
      sequenceDurations
%       userSequenceDuration
%       userSequenceDataDuration
%       adjustedSequenceDuration
%       adjustedSequenceDataDuration
%       sentSequenceDuration
%       sentSequenceDataDuration
      %userSequence (below) is a special case here. I originally wanted it
      %to be not read-only. Unfortunately, there are multiple ways to
      %represent which channels are on (base 10, binary, and names) so it
      %is necessary to change each representation for each set command.
      %Doubly unfortunately, the "set.propertyname" function is basically
      %useless for structures as input argument for it is the
      %already-modified structure. Because of this, I have 3 functions for
      %modifying this property: addPulse, modifyPulse, and deletePulse
      userSequence
   end

   properties (Dependent, SetAccess = protected, GetAccess = public)
      %Read-only for user, derived from other values      
      nChannels
   end

   methods

      function h = pulse_blaster(configFileName)

          if nargin < 1
              error('Config file name required as input')
          end

         %Loads config file and checks relevant field names
         configFields = {'clockSpeed','identifier','nChannels','formalDirectionNames',...
            'acceptableDirectionNames','formalChannelNames','acceptableChannelNames'};
         commandFields = {'library','api','type','name'};%Use commands to hold dll info
         numericalFields = {};      
         h = loadConfig(h,configFileName,configFields,commandFields,numericalFields);
      end

      function h = connect(h)
         if h.connected
            warning('Pulse blaster is already connected')
            return
         end

         if ~libisloaded(h.commands.name)
             warning('off','MATLAB:loadlibrary:FunctionNotFound') %Produces warning for pb_get_rounded_value not being in library
             loadlibrary(h.commands.library, h.commands.api, 'addheader',h.commands.type);
             warning('on','MATLAB:loadlibrary:FunctionNotFound')
         end

         [~] = calllib(h.commands.name,'pb_init');
         calllib(h.commands.name,'pb_core_clock',h.clockSpeed);

         h.connected = true;
         h.identifier = 'pulse blaster';
      end

      function h = disconnect(h)
         if ~h.connected    
             return;   
         end
         if ~isempty(h.commands)
            h.commands = [];
         end
         h.connected = false;
      end
      
      function h = addPulse(h,pulseInfo,varargin)

         %Adds a pulse to the sequence. If a third argument is given,
         %inserts the pulse at that location within the sequence

         %Argument validation
         mustContainField(pulseInfo,'duration')
         if sum(isfield(pulseInfo,{'numericalOutput','channelsBinary','activeChannels'})) ~= 1
            error('Pulse info (2nd argument) must contain exactly one of the following: numericalOutput, channelsBinary, or activeChannels')
         end
         if pulseInfo.duration <= 0 || pulseInfo.duration > 8.589e9
            error('Pulse duration must be between 0 and 8.589e9. Input duration: %g',pulseInfo.duration)
         end

         %Syncs numericalOutput, channelsBinary, and activeChannels. Puts
         %everything into the correct format
         if isfield(pulseInfo,'activeChannels')
            %Removes empty entries in active channels
            pulseInfo.activeChannels(cellfun(@isempty,(pulseInfo.activeChannels))) = [];
            [pulseInfo.numericalOutput,pulseInfo.channelsBinary] = interpretPulseNames(h,pulseInfo.activeChannels);
         elseif isfield(pulseInfo,'channelsBinary')
            pulseInfo.numericalOutput = bin2dec(fliplr(pulseInfo.channelsBinary));
         end
         [pulseInfo.activeChannels,pulseInfo.channelsBinary] = interpretPulseNames(h,pulseInfo.numericalOutput);

         %Set of defaults if user does not input values. These either are
         %unnecessary or are almost always one thing unless otherwise
         %stated
         if ~isfield(pulseInfo,'notes')%Optional, just to remember what each pulse is
            pulseInfo.notes = '';
         end
         if ~isfield(pulseInfo,'contextInfo')%Usually unneeded
            pulseInfo.contextInfo = 0;
         end

         if ~isfield(pulseInfo,'directionType')
            pulseInfo.directionType = h.formalDirectionNames{1};
         else
            %Interprets user command to a direction the instrument can
            %understand
            pulseInfo.directionType = interpretName(h,pulseInfo.directionType,'Direction');
         end

         %Pulse info now has notes, contextInfo, directionType, duration,
         %activeChannels, channelsBinary, and numericalOutput
         pulseInfo = orderfields(pulseInfo,{'activeChannels','channelsBinary','numericalOutput',...
            'duration','directionType','contextInfo','notes'});

         %Adds to sequence structure. If an additional argument is given,
         %use that argument to determine where in the sequence the pulse
         %will be inserted
         if nargin > 2 && ~isempty(varargin{1})
            h.userSequence = instrumentType.addStructIndex(h.userSequence,pulseInfo,varargin{1});
         else
            h.userSequence = instrumentType.addStructIndex(h.userSequence,pulseInfo);
         end

         %If 4th argument is true, adjust sequence
         if nargin < 4 || ~varargin{2}
             return
         end

%          if h.sendUponAddition
%             %Sends the new pulse sequence to the pulse blaster if enabled
%             h = sendToInstrument(h);
%          else
%             %After changing the sequence, perform adjustment to get up to
%             %date adjusted sequence (doesn't change user sequence)
%             %Unneeded if being sent as sendToInstrument does this already
%             h = adjustSequence(h);
%          end

      end

      function [h] = condensedAddPulse(h,activeChannels,duration,notes,varargin)
         %Single line version of add pulse for "normal" pulses
         pulseInfo.activeChannels = activeChannels;
         pulseInfo.duration = duration;
         pulseInfo.notes = notes;
         h = addPulse(h,pulseInfo);
      end

      function h = adjustSequence(h)
         %Adjusts sequence to include total loop (if enabled) as well as
         %necessary stop pulse

         %Copy user sequence to the adjusted sequence
         h.adjustedSequence = h.userSequence;

         if isempty(h.userSequence)%No sequence
            h = calculateDuration(h,'user');
            h = calculateDuration(h,'adjusted');
            return
         end

         %All the extra pulses have these properties
         pulseInfo.activeChannels = {};
         pulseInfo.channelsBinary = num2str(zeros(1,h.nChannels));
         pulseInfo.numericalOutput = 0;
         pulseInfo.duration = 20;%Minimum suggested time for some pulses

         if h.useTotalLoop
            %Beginning of total loop
            pulseInfo.directionType = h.formalDirectionNames{3};%Start loop
            pulseInfo.contextInfo = h.nTotalLoops;
            pulseInfo.notes = 'Total loop beginning';
            h.adjustedSequence(2:end+1) = h.adjustedSequence;
            h.adjustedSequence(1) = pulseInfo;

            %End of total loop
            pulseInfo.directionType = h.formalDirectionNames{4};%End loop
            pulseInfo.contextInfo = 0;
            pulseInfo.notes = 'Total loop end';
            h.adjustedSequence(end+1) = pulseInfo;
         end

         %An empty pulse of 20 ns is suggested before running the stop
         %pulse according to SpinCore
         pulseInfo.contextInfo = 0;
         pulseInfo.directionType = h.formalDirectionNames{1};%Continue
         pulseInfo.notes = 'Buffer before stopping sequence';
         h.adjustedSequence(end+1) = pulseInfo;

         %Stops the sequence. Necessary for every sequence as the pulse
         %blaster is unhappy if the sequence ends without one
         pulseInfo.directionType = h.formalDirectionNames{2};%Stop
         pulseInfo.notes = 'Stop sequence';
         h.adjustedSequence(end+1) = pulseInfo;

         %Calculates durations for the user and adjusted sequence
         h = calculateDuration(h,'user');
         h = calculateDuration(h,'adjusted');
      end

      function h = sendToInstrument(h)
         h = adjustSequence(h);%Adjusts sequence in preparation to send to instrument

         %Saves the current adjusted sequence as the sequence that has
         %been sent to the pulse blaster
         h.sequenceSentToPulseBlaster = h.adjustedSequence;
         h = calculateDuration(h,'sent');

         [~] = calllib(h.commands.name,'pb_start_programming',0);%Unsure what 0 does***

         %For each pulse, check the direction to find the corresponding op
         %code. Additionally, keep track of all loops so that an end
         %loop command ends the most recent loop.
         loopTracker = [];
         for ii = 1:numel(h.adjustedSequence)
            current = h.adjustedSequence(ii);

            [~,opCode] = interpretName(h,current.directionType,'Direction');

            if opCode == 3%Start loop
               loopTracker(end+1) = ii; %#ok<AGROW>
            elseif opCode == 4%End loop
               if isempty(loopTracker),   error('Attempted to end loop while no loop has begun'),    end
               current.contextInfo = loopTracker(end);
               loopTracker(end) = [];
            end
            %Sends the current instruction to the pulse blaster
            [~] = calllib(h.commands.name,'pb_inst_pbonly',current.numericalOutput,...
               opCode-1,current.contextInfo,round(current.duration));
         end

         [~] = calllib(h.commands.name,'pb_stop_programming');
      end

      function h = modifyPulse(h,addressNumber,fieldToModify,modifiedValue,varargin)
         arguments
            h
            addressNumber {mustBeNumeric}
            fieldToModify {mustBeA(fieldToModify,["string","char"])}
            modifiedValue           
         end
         arguments (Repeating)
            varargin
         end

         %Default to adjusting the sequence if not given
         if nargin >= 5
            boolAdjust = varargin{1};
         else
            boolAdjust = true;
         end

         if any(addressNumber > numel(h.userSequence))
            error('Sequence is only %d pulses long, cannot modify pulse %d',numel(h.userSequence),max(addressNumber))
         end

         switch lower(fieldToModify)

            case {'activechannels','channels','active','names','name'}%Active channels, match binary and output then reorder
               if ~isa(modifiedValue,'cell')
                  error('activeChannels modified value must be a cell of character arrays')
               end
               for currentAddress = addressNumber
                  [h.userSequence(currentAddress).numericalOutput,h.userSequence(currentAddress).channelsBinary]= interpretPulseNames(h,modifiedValue);
                  [h.userSequence(currentAddress).activeChannels,~] = interpretPulseNames(h,h.userSequence(currentAddress).numericalOutput);
               end

            case {'channelsbinary','binary','binarychannels'}%Convert binary to numerical output then find activeChannels and properly structured binary
               if ~isa(modifiedValue,'char'),    error('Binary output must be a character array'),    end
               for currentAddress = addressNumber
                  h.userSequence(currentAddress).numericalOutput = bin2dec(fliplr(modifiedValue));
                  [h.userSequence(currentAddress).activeChannels,h.userSequence(currentAddress).channelsBinary]= interpretPulseNames(h,modifiedValue);
               end
            case {'numericaloutput','output','numerical','number','value'}%Output simple replace then match binary and channel names
               for currentAddress = addressNumber
                  h.userSequence(currentAddress).numericalOutput = modifiedValue;
                  [h.userSequence(currentAddress).activeChannels,h.userSequence(currentAddress).channelsBinary]= interpretPulseNames(h,modifiedValue);
               end

            case {'duration','dur','time'}%Duration simple replacement
               if modifiedValue < 0
                  error('Duration cannot be negative')
               end
               for currentAddress = addressNumber
                  h.userSequence(currentAddress).duration = modifiedValue;
               end

            case {'directiontype','direction','type'}%Duration intepret direction then replace
               for currentAddress = addressNumber
                  h.userSequence(currentAddress).directionType = interpretName(h,modifiedValue,'Direction');
               end

            case {'contextinfo','context'}%Context info simple replacement
               for currentAddress = addressNumber
                  h.userSequence(currentAddress).contextInfo = modifiedValue;
               end

            case {'notes','usernotes','description'}%Notes simple replacement
               for currentAddress = addressNumber
                  h.userSequence(currentAddress).notes = modifiedValue;
               end

         end
         if boolAdjust
            h = calculateDuration(h,'user');
         end

      end

      function h = deletePulse(h,addressNumber)
         %Deletes all pulses given by addressNumber
         %Sorts the addresses by descending to prevent a shifting sequence
         %accidentally changing which pulses are deleted
         addressNumber = sort(addressNumber,'descend');
         for ii = 1:numel(addressNumber)
            h.userSequence(addressNumber) = [];
         end
         h = adjustSequence(h);
      end

      function h = calculateDuration(h,sequenceType)
         %Calculates the total time of the user sequence as well as the
         %time spent on data collection in the user sequence. Also does
         %this for the final sequence after adding the total loop that
         %would be sent to the pulseBlaster

         %Note: I am certain that this code could be better written,
         %however it currently works and it is not worth the time/effort
         %that would be required to rewrite it

         %Break the pulse sequence into "chunks" that will be individually
         %evaluated based on what loops they are inside, the cumulative
         %result of which is the total duration

         switch lower(sequenceType)
            case 'user'
               sequence = h.userSequence;
            case 'adjusted'
               sequence = h.adjustedSequence;
            case 'sent'
               sequence = h.sequenceSentToPulseBlaster;
            otherwise
               error('totalOrData input (arg 2) must be "data" or "total"')
         end

         if isempty(sequence)
             h.sequenceDurations.(sequenceType).totalNanoseconds = 0;
             h.sequenceDurations.(sequenceType).totalSeconds = 0;
             h.sequenceDurations.(sequenceType).dataNanoseconds = 0;
             h.sequenceDurations.(sequenceType).dataFraction = 0;
             return
         end

         %Gets the name of the channel with an acceptable name "data"
         %This is why it is important to have "data" be an acceptable name
         try
            [dataName,~] = interpretName(h,'data','Channel');
         catch
            dataName = [];
         end

         durationValues = [sequence.duration];%Values for duration of each pulse
         dataOn = false(numel(sequence),1);%Defaults data to false

         %The loop below finds the start and end locations for all loops
         %within the sequence
         startTracker = [];
         loopTracker = [];
         nLoopsTracker = [];
         for jj = 1:numel(sequence)
            current = sequence(jj);

            %Checks opCode for the current direction
            [~,opCode] = interpretName(h,current.directionType,'Direction');

            if opCode == 3%Start loop
               %Add to start tracker and number of loops tracker
               startTracker(end+1) = jj; %#ok<AGROW>
               nLoopsTracker(end+1) = current.contextInfo;%#ok<AGROW>
            elseif opCode == 4%End loop
               if isempty(startTracker),   error('Attempted to end loop while no loop has begun'),    end
               %Adds both the start and number of loops to a new row on
               %loop tracker then removes those values from their own
               %tracker to prevent using them again
               loopTracker(end+1,1) = startTracker(end);%#ok<AGROW>
               startTracker(end) = [];
               loopTracker(end,3) = nLoopsTracker(end);
               nLoopsTracker(end) = [];
               loopTracker(end,2) = jj;
               %This effecitvely sorts the loops based on where the end
               %loop comes first but this is irrelevant as it will only
               %be used in a resorted form or in a form directly
               %referenced based on this order
            end

            %If there is a data name and the data name matches an active
            %channel of the current pulse, mark this as data collection
            %on
            if ~isempty(dataName) && ismember(dataName,current.activeChannels)
               dataOn(jj) = true;
            end

         end

         totalDuration = 0;
         dataDuration = 0;

         if ~isempty(loopTracker)
            %Gets rid of start/end distinction to set the chunk
            %boundaries at every change in the loop configuration (every
            %start or end of a loop)
            chunks = sort(reshape(loopTracker(:,1:2),1,(2/3)*numel(loopTracker)),'ascend');

            for jj = 1:numel(chunks)-1
               chunkStart = chunks(jj);
               chunkEnd = chunks(jj+1);
               %Finds the pulses between chunk boundaries
               if chunkStart+1<= chunkEnd-1
                  interiorPulses = chunkStart+1:1:chunkEnd-1;
               else
                  interiorPulses = [];
               end

               %Include end loops on first possible chunk, include start
               %loops on second possible chunk
               [~,opCode] = interpretName(h,sequence(chunkEnd).directionType,'Direction');
               if opCode == 4%End Loop
                  interiorPulses(end+1) = chunkEnd; %#ok<AGROW>
               end

               [~,opCode] = interpretName(h,sequence(chunkStart).directionType,'Direction');
               if opCode == 3%Start Loop
                  interiorPulses(2:end+1) = interiorPulses;
                  interiorPulses(1) = chunkStart;
               end

               if ~isempty(interiorPulses)
                  %Find what loops they are inside
                  insideLoops =  interiorPulses(1) >= loopTracker(:,1) & interiorPulses(1) <= loopTracker(:,2);

                  %Find duration of chunk as well as what ratio of the
                  %chunk is taking data
                  chunkDuration = durationValues(interiorPulses);
                  dataRatio = sum(chunkDuration(dataOn(interiorPulses)));
                  chunkDuration = sum(chunkDuration);
                  dataRatio = dataRatio/chunkDuration;

                  %Multiply by the loops it is in
                  chunkDuration = prod(loopTracker(insideLoops,3))*chunkDuration;

                  %Add to total
                  totalDuration = totalDuration + chunkDuration;
                  dataDuration = dataDuration + chunkDuration*dataRatio;
               end
            end            

         else
            totalDuration = sum(durationValues);
            dataDuration = sum(durationValues(dataOn));
         end

         h.sequenceDurations.(sequenceType).totalNanoseconds = totalDuration;
         h.sequenceDurations.(sequenceType).totalSeconds = totalDuration * 1e-9;
         h.sequenceDurations.(sequenceType).dataNanoseconds = dataDuration;
         h.sequenceDurations.(sequenceType).dataFraction = dataDuration/totalDuration;

      end

      function [outVal,outputBinary] = interpretPulseNames(h,inVal)
         mustBeA(inVal,["cell","double"])
         %Swaps between channel names and numerical output depending on
         %what is put in

         %Creates character array of 0s
         outputBinary  = num2str(zeros(1,h.nChannels));

         if isa(inVal,'cell') || isa(inVal,'char') || isa(inVal,'string')
            inVal = string(inVal);
            outVal = 0;
            if isempty(inVal),   return,   end%No active channels
            for ii = inVal
               [~,n] = interpretName(h,ii,'Channel');
               cn = (h.nChannels+1) - n;
               if strcmp(outputBinary(3*cn-2),'0')
                  outputBinary(3*cn-2) = '1';
                  outVal = outVal + 2^(n-1);
               else
                  error('Repeated %s pulse name',interpretName(h,ii{1},'Channel'))
               end
            end
            return
         end

         inVal = dec2bin(inVal);
         activeChannels = find(inVal=='1')+(h.nChannels-numel(inVal));
         outputBinary(3*(activeChannels-1)+1) = '1';
         outVal = cell(1,numel(activeChannels));
         for ii = 1:numel(activeChannels)
            outVal{ii} = h.formalChannelNames{(h.nChannels - activeChannels(ii))+1};
         end
         outVal = fliplr(outVal);%Flips order to what user would be familiar with

      end

      function runSequence(h)
         [~] = calllib(h.commands.name,'pb_start');
      end

      function stopSequence(h)
         [~] = calllib(h.commands.name,'pb_stop');
      end

      function status = pbRunning(h)
         %Checks if the pulse blaster is currently running
         status = calllib(h.commands.name,'pb_read_status') == 4;

         %If this dll file is called outside this function and returns -1
         %then the installation of the pulse blaster files is
         %corrupted somehow and needs to be redownloaded
      end

      function [interpretedString,matchingNumber] = interpretName(h,inputName,nameType)
         %nameType should be Channel or Direction
         %Creates an anonymous function that compares the input string to
         %acceptable names from the config

         inputName = string(inputName);

         %Preallocation
         interpretedString = cell(1,numel(inputName));
         matchingNumber = zeros(1,numel(inputName));

         for ii = 1:numel(inputName)
            %Creates function that compares namesCell to the current
            %inputName
            checkName = @(namesCell)any(strcmpi(namesCell,inputName(ii)));
            %Finds which cells contain an acceptable name matching the
            %input
            matchingName = cellfun(checkName,h.(strcat('acceptable',nameType,'Names')));
            if ~any(matchingName), error('%s is not an acceptable %s name',inputName,nameType), end

            %Gets the formal name wherever the input matched an
            %accceptable name
            interpretedString{ii} = h.(strcat('formal',nameType,'Names')){matchingName};
            matchingNumber(ii) = find(matchingName);
         end
      end

      function pulseNumbers = findPulses(h,categoryToCheck,pulseSignifier,varargin)
         %Find all pulse numbers that have the input signifier for the
         %category given

         switch lower(categoryToCheck)
            case {'notes','usernotes','description'}
               %Checks user notes to see if signifier corresponds to them
               if nargin ~= 4
                  error('findPulses must have a 4th argument that is "contains" or "matches" if notes category is used')
               end
               allNotes = {h.userSequence.notes};

               %If 'contains' is given, check if notes contain a signifier.
               %If 'matches' is given, check if notes exactly match
               %signifier
               if strcmp(varargin{1},'contains')
                  pulseNumbers = find(contains(lower(allNotes),lower(pulseSignifier)));
               elseif strcmp(varargin{1},'matches')
                  pulseNumbers = find(strcmpi(allNotes,pulseSignifier));
               else
                  error('findPulses must have a 4th argument that is "contains" or "matches" if notes category is used')
               end

            case {'duration','dur','time'}
               %If the duration equals the signifier, output that pulse
               %number
               pulseNumbers = find(cellfun(@(x)x==pulseSignifier,{h.userSequence.duration}));
             case {'activechannels','channels','active','names','name','active channels'}
               %Checks user notes to see if signifier corresponds to them
               if nargin ~= 4
                  error('findPulses must have a 4th argument that is "contains" or "matches" if activeChannels category is used')
               end
               allChannels = {h.userSequence.activeChannels};
               pulseSignifier = string(pulseSignifier);

               if strcmp(varargin{1},'contains')
                  %If any of the channel names match the input signifier,
                  %return true. Do this for every pulse
                  pulseNumbers = find(cellfun(@(x)any(strcmpi(x,pulseSignifier)),allChannels));
               elseif strcmp(varargin{1},'matches')
                  %If all pulses of the signifier match all pulses of the
                  %given pulse, return true. Do this for every pulse
                  pulseNumbers = find(cellfun(@(x)all(ismember(pulseSignifier,x))&&all(ismember(x,pulseSignifier)),allChannels));
               else
                  error('findPulses must have a 4th argument that is "contains" or "matches" if activeChannels category is used')
               end
            case {'directiontype','direction','type'}
               pulseNumbers = find(strcmpi({h.userSequence.direction},pulseSignifier));
         end
      end

      function durations = calculatePulseModifications(h,addressesToModify,modifierAddresses,varargin)
         %Calculates what the new duration should be by modifying old
         %durations based on durations of pulses at the modifier
         %adresses

         %input 4: calculation method
         %input 5: calculation location
         %input 6: durations of addresses to modify (for scan
         %calculations)

         %If no calculation method is input, default to subtract
         if nargin >= 4 && ~isempty(varargin{1})
            calculationMethod = varargin{1};
            if ~ismember(lower(string(calculationMethod)),["subtract","add"])
               error('%s is not a valid calculation location',calculationMethod)
            end
         else
            calculationMethod = 'subtract';
         end
         %If no calculation location is input, default to both
         if nargin >= 5 && ~isempty(varargin{2})
            calculationLocation = varargin{2};
            if ~ismember(lower(string(calculationLocation)),["before","after","both"])
               error('%s is not a valid calculation location',calculationLocation)
            end
         else
            calculationLocation = 'both';
         end
         %If no duration is input, default to duration of the
         %addressesToModify
         if nargin >= 6 && ~isempty(varargin{3})
            durations = varargin{3};
            if numel(durations) ~= numel(addressesToModify)
               error('Number of addresses to modify (%i) does not match number of durations input (%i)'...
                  ,numel(addressesToModify),numel(durations))
            end
         else
            durations = [h.userSequence(addressesToModify).duration];
         end

         %Calculates new duration for pulses before this one
         if strcmpi(calculationLocation,'before') || strcmpi(calculationLocation,'both')
            for ii = 1:numel(durations)
               %Sends to function to calculate the new duration
               durations(ii) = calculateNewDuration(h,durations(ii),...
                  modifierAddresses,addressesToModify(ii)-1,calculationMethod);
            end
         end
         %Repeat for after
         if strcmpi(calculationLocation,'after') || strcmpi(calculationLocation,'both')
            for ii = 1:numel(durations)
               %Sends to function to calculate the new duration
               durations(ii) = calculateNewDuration(h,durations(ii),...
                  modifierAddresses,addressesToModify(ii)+1,calculationMethod);
            end
         end

         function newDuration = calculateNewDuration(h,oldDuration,allAddresses,currentAddress,calculationMethod)
            %Calculates new duration based on old duration, address
            %that modifies the duration, and calculation method

            if ~ismember(currentAddress,allAddresses)
               newDuration = oldDuration;
               return
            end

            modifierLocation = allAddresses(allAddresses == currentAddress);
            switch lower(calculationMethod)
               case 'subtract'
                  newDuration = oldDuration - h.userSequence(modifierLocation).duration;
                  if newDuration < 0
                     error('Duration of a pulse cannot be negative')
                  end
               case 'add'
                  newDuration = oldDuration + h.userSequence(modifierLocation).duration;
            end

         end


      end

      function h = addBuffer(h,pulseAddresses,bufferDuration,channelsToCopy,varargin)
         %Argument 7 is notes, argument 6 is before/after
         %Beofre/after only needed if a single value is given

         channelsToCopy = interpretName(h,channelsToCopy,'Channel');

         if ~all(bufferDuration == 0)
            for ii = 1:numel(pulseAddresses)

               currentAddress = pulseAddresses(end-(ii-1)); %Goes backwards to keep easy indexing
               pulseInfo = [];
               pulseInfo.activeChannels = {};

               %Add channels based on pulse the buffer corresponds to
               for jj = 1:numel(channelsToCopy)
                  if any(strcmpi(h.userSequence(currentAddress).activeChannels,channelsToCopy{jj}))
                     pulseInfo.activeChannels{end+1} = channelsToCopy{jj};
                  end
               end

               %Add notes if given
               if nargin >= 6
                  pulseInfo.notes = varargin{2};
               end

               if ~isscalar(bufferDuration)
                  %First buffer duration is the "before" and second is "after"
                  %Perform "after" buffer first to keep indexing simple
                  if bufferDuration(2) ~= 0
                     pulseInfo.duration = bufferDuration(2);                     
                     h = addPulse(h,pulseInfo,currentAddress+1);
                  end
                  if bufferDuration(1) ~= 0
                     pulseInfo.duration = bufferDuration(1);                    
                     h = addPulse(h,pulseInfo,currentAddress);
                  end
               else %Only 1 duration given
                  if nargin < 5
                     error('If only a single duration is given, the location of the buffer must be specified as "before" or "after"')
                  end
                  pulseInfo.duration = bufferDuration;                  
                  if strcmpi(varargin{1},'before')
                     h = addPulse(h,pulseInfo,currentAddress);
                  elseif strcmpi(varargin{1},'after')
                     h = addPulse(h,pulseInfo,currentAddress+1);
                  else
                     error('If only a single duration is given, the location of the buffer must be specified as "before" or "after"')
                  end
               end
            end
         end
         h = adjustSequence(h);         
      end

      function [h,scanInfo] = loadTemplate(h,templateName,params)
         %Runs function if one exists that matches templateName         
         [h,~,scanInfo] = feval(templateName,h,params);

         %Technically, these should really be functions of the pulse blaster object, however it is easier to write a new template
         %in its own file and later determine what all the possible templates are by making them independent functions in their
         %own folder
      end

      % function h = showSequence(h,userOrAdjusted)
      %    %Display similar to pulseSequenceEditor
      %    h.plots.fig = figure;
      %    h.plots.ax = axes(h.plots.fig);
      % 
      % 
      % 
      % 
      % end

      function h = deleteSequence(h)
          h.userSequence = [];
          h = adjustSequence(h);
      end
      
      function val = get.nChannels(h)
         val = numel(h.formalChannelNames);
      end

   end
   methods (Static)
      function params = queryTemplateParameters(templateName)
         %Obtains the template parameters from a function with the given template name
         [~,params] = feval(templateName,[],[]);
      end
   end
end