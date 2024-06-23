function XYn_Beta_Branch(templateInputs)
%Loads a Rabi sequence and scan based on given RF frequency and duration inputs
%Minimum τ is 80 b/c minimum τ/2 is 40 due to I/Q delay

%Requires:
%pi divisible by 4
%Tau at least 2*(10+3pi/4 + extraRF)    %typically at least 100
%Tau is even

global master

%If this is an input request, give the input names. Otherwise, generate the
%pulse sequence  and perform other operations using the inputs given.
if strcmp(templateInputs,'inputs request')
   
   %Remove the old list of input names if present. Do not change
   if isfield(master.gui.PSE,'inputNames')
      master.gui.PSE = rmfield(master.gui.PSE,'inputNames');
   end
   
   %For each input in your pulse sequence add the name you want displayed
   %in the template tab of the PulseSequenceEditor
   master.gui.PSE.inputNames(1) = "RF resonance frequency";
   master.gui.PSE.inputNames(2) = "π";
   master.gui.PSE.inputNames(3) = "τ start";
   master.gui.PSE.inputNames(4) = "τ end";
   master.gui.PSE.inputNames(5) = "τ steps";
   master.gui.PSE.inputNames(6) = "n XY";
   master.gui.PSE.inputNames(7) = "r sets of XYn";
   master.gui.PSE.inputNames(8) = "Collection time*";
   master.gui.PSE.inputNames(9) = "RF duration reduction*";
   master.gui.PSE.inputNames(10) = "AOM buffer duration*";
   master.gui.PSE.inputNames(11) = "I/Q buffer pre*";
   master.gui.PSE.inputNames(12) = "I/Q buffer post*";
   master.gui.PSE.inputNames(13) = "I/Q pre duration*";
   master.gui.PSE.inputNames(14) = "I/Q post duration*";
   return
end

%Deletes the old sequence if present. Do not change
if isfield(master.PB,'sequence')
   master.PB = rmfield(master.PB,'sequence');
end

%% Calculations and shorthand

%Shorthand notation for inputs
master.RF.frequency = str2double(templateInputs{1});
piDuration = str2double(templateInputs{2});
startDuration = str2double(templateInputs{3});
endDuration = str2double(templateInputs{4});
nSteps = str2double(templateInputs{5});
nXY = str2double(templateInputs{6});
rSets = str2double(templateInputs{7});
collectionTime = str2double(templateInputs{8});
extraRF = str2double(templateInputs{9});
AOMBuffer = str2double(templateInputs{10});
preBuffer = templateInputs{11};
postBuffer = templateInputs{12};
preDuration = str2double(templateInputs{13});
postDuration = str2double(templateInputs{14});

if collectionTime == 0
   collectionTime = 1000;
end

switch lower(preBuffer)
   case {'0','f','false','no','n','off'}
      preBuffer = false;
   case {'1','t','true','yes','y','on'}
      preBuffer = true;
   otherwise
      error('invalid pre buffer input')
end

switch lower(postBuffer)
   case {'0','f','false','no','n','off'}
      postBuffer = false;
   case {'1','t','true','yes','y','on'}
      postBuffer = true;
   otherwise
      error('invalid post buffer input')
end

if mod(nXY,4) ~= 0
   error('n must be divisible by 4')
end

%Sets RF value to resonance
if isfield(master.RF,'initialized')
   if master.RF.initialized
      RFFrequency
      master.RF.modulationOn = true;
      master.RF.modulationType = 'I/Q';
   end
end

master.NIDAQ.useClock = true;

master.PB.addTotalLoops = true;
master.PB.totalLoops = 1e5;

%% Creation of the pulse sequence using custom inputs
%Each pulse in a sequence must have an output, direction, and duration
%as well as a contextinfo in some cases. Once these have been input,
%running the PBAddSequence command will add a new pulse with the current
%settings to the end of the sequence. See the end of this function for
%information about valid values for each of these.

%Signal vs Reference loop
for jj  = 1:2
   
   if jj == 1
      sigref = 0;
      finalPi2Output = 56+sigref;
   else         
      if master.NIDAQ.confocal
         sigref = 4;
      else
         sigref = 0;
      end
      finalPi2Output = 8+sigref;
   end
   
   %1 - Buffer at start of loop gives time for AOM to turn off before RF
   %pulse
   master.PB.command.description = 'AOM buffer';
   master.PB.command.output = sigref;
   master.PB.command.direction = 'CONTINUE';
   master.PB.command.duration = 2500;
   PBAddSequence
   
   if ~master.NIDAQ.confocal
      
      %1.1 - S/R for wide field
      master.PB.command.description = 'WF signal/reference';
      master.PB.command.output = 4;
      master.PB.command.direction = 'CONTINUE';
      master.PB.command.duration = 25;
      PBAddSequence
      
      if jj == 1
         %1.2 - S/R for wide field
         master.PB.command.description = 'WF gap';
         master.PB.command.output = 0;
         master.PB.command.direction = 'CONTINUE';
         master.PB.command.duration = 25;
         PBAddSequence
         
         %1.3 - S/R for wide field
         master.PB.command.description = 'WF signal';
         master.PB.command.output = 4;
         master.PB.command.direction = 'CONTINUE';
         master.PB.command.duration = 25;
         PBAddSequence
         
      end
      
   end
   
   if preBuffer
      %1.4 - I/Q pre-buffer
      master.PB.command.description = 'I/Q pre-buffer';
      master.PB.command.output = sigref;
      master.PB.command.direction = 'CONTINUE';
      master.PB.command.duration = preDuration;
      PBAddSequence
   end
   
   %2 - π/2 x
   master.PB.command.description = 'Initial pi/2 x';
   master.PB.command.output = 8+sigref;
   master.PB.command.direction = 'CONTINUE';
   master.PB.command.duration = extraRF + piDuration/2;
   PBAddSequence
   
   if postBuffer
      %2.1 - I/Q post-buffer
      master.PB.command.description = 'I/Q post-buffer';
      master.PB.command.output = sigref;
      master.PB.command.direction = 'CONTINUE';
      master.PB.command.duration = postDuration;
      PBAddSequence
   end

   % end loop pulse
   master.PB.command.description = 'Extra end loop pulse';
   master.PB.command.output = sigref;
   master.PB.command.duration = 10;
   master.PB.command.direction = 'LOOP';
   master.PB.command.contextinfo = rSets;
   PBAddSequence
   
   for ii = 1:nXY/4
      
      if mod(ii,2) == 1 %Odd set
         firstpulse = 24+sigref; %I and RF is on (y)
         secondpulse = 8+sigref; %I is off and RF is on (x)
      else %Even set
         firstpulse = 8+sigref; %I and RF is on (x)
         secondpulse = 24+sigref; %I is off and RF is on (y)
      end
      
      %3 - τ/2 first
      master.PB.command.description = 'Scanned tau/2';
      master.PB.command.output = sigref;
      master.PB.command.duration = 50; %Overwritten by scan
%       if ii == 1
%          master.PB.command.direction = 'LOOP';
%          master.PB.command.contextinfo = rSets;
%       else
         master.PB.command.direction = 'CONTINUE';
%       end
      PBAddSequence
      
      if preBuffer
         %3.1 - I/Q pre-buffer
         master.PB.command.description = 'I/Q pre-buffer';
         master.PB.command.output = firstpulse-8;
         master.PB.command.direction = 'CONTINUE';
         master.PB.command.duration = preDuration;
         PBAddSequence
      end
      
      %4 - π first
      master.PB.command.description = 'first pi';
      master.PB.command.output = firstpulse;
      master.PB.command.direction = 'CONTINUE';
      master.PB.command.duration = extraRF + piDuration;
      PBAddSequence
      
      if postBuffer
         %4.1 - I/Q post-buffer
         master.PB.command.description = 'I/Q post-buffer';
         master.PB.command.output = firstpulse-8;
         master.PB.command.direction = 'CONTINUE';
         master.PB.command.duration = postDuration;
         PBAddSequence
      end
      
      %5 - τ second
      master.PB.command.description = 'Scanned second tau';
      master.PB.command.output = sigref;
      master.PB.command.direction = 'CONTINUE';
      master.PB.command.duration = 100; %Overwritten by scan
      PBAddSequence
      
      if preBuffer
         %5.1 - I/Q pre-buffer
         master.PB.command.description = 'I/Q pre-buffer';
         master.PB.command.output = secondpulse-8;
         master.PB.command.direction = 'CONTINUE';
         master.PB.command.duration = preDuration;
         PBAddSequence
      end
      
      %6 - π second
      master.PB.command.description = 'Second pi';
      master.PB.command.output = secondpulse;
      master.PB.command.direction = 'CONTINUE';
      master.PB.command.duration = extraRF + piDuration;
      PBAddSequence
      
      if postBuffer
         %6.1 - I/Q post-buffer
         master.PB.command.description = 'I/Q post-buffer';
         master.PB.command.output = secondpulse-8;
         master.PB.command.direction = 'CONTINUE';
         master.PB.command.duration = postDuration;
         PBAddSequence
      end
      
      %7 - τ first
      master.PB.command.description = 'Scanned third tau';
      master.PB.command.output = sigref;
      master.PB.command.direction = 'CONTINUE';
      master.PB.command.duration = 100; %Overwritten by scan
      PBAddSequence
      
      if preBuffer
         %7.1 - I/Q pre-buffer
         master.PB.command.description = 'I/Q pre-buffer';
         master.PB.command.output = firstpulse-8;
         master.PB.command.direction = 'CONTINUE';
         master.PB.command.duration = preDuration;
         PBAddSequence
      end
      
      %8 - π first
      master.PB.command.description = 'Third pi';
      master.PB.command.output = firstpulse;
      master.PB.command.direction = 'CONTINUE';
      master.PB.command.duration = extraRF + piDuration;
      PBAddSequence
      
      if postBuffer
         %8.1 - I/Q post-buffer
         master.PB.command.description = 'I/Q post-buffer';
         master.PB.command.output = firstpulse-8;
         master.PB.command.direction = 'CONTINUE';
         master.PB.command.duration = postDuration;
         PBAddSequence
      end
      
      %9 - τ second
      master.PB.command.description = 'Scanned fourth tau';
      master.PB.command.output = sigref;
      master.PB.command.direction = 'CONTINUE';
      master.PB.command.duration = 100; %Overwritten by scan
      PBAddSequence
      
      if preBuffer
         %9.1 - I/Q pre-buffer
         master.PB.command.description = 'I/Q pre-buffer';
         master.PB.command.output = secondpulse-8;
         master.PB.command.direction = 'CONTINUE';
         master.PB.command.duration = preDuration;
         PBAddSequence
      end
      
      %10 - π second
      master.PB.command.description = 'Fourth pi';
      master.PB.command.output = secondpulse;
      master.PB.command.direction = 'CONTINUE';
      master.PB.command.duration = extraRF +  piDuration;
      PBAddSequence
      
      if postBuffer
         %10.1 - I/Q post-buffer
         master.PB.command.description = 'I/Q post-buffer';
         master.PB.command.output = secondpulse-8;
         master.PB.command.direction = 'CONTINUE';
         master.PB.command.duration = postDuration;
         PBAddSequence
      end
      
      %11 - τ/2 last
      master.PB.command.description = 'Scanned tau/2';
      master.PB.command.output = sigref;
      master.PB.command.duration = 50; %Overwritten by scan
      master.PB.command.direction = 'CONTINUE';      
      PBAddSequence
      
   end

   % end loop pulse
   master.PB.command.description = 'Extra end loop pulse';
   master.PB.command.output = sigref;
   master.PB.command.duration = 10; %Overwritten by scan
   master.PB.command.contextinfo = 7;
   master.PB.command.direction = 'END_LOOP';
   PBAddSequence

   if preBuffer
      %11.1 - I/Q pre-buffer
      master.PB.command.description = 'I/Q pre-buffer';
      master.PB.command.output = finalPi2Output-8;
      master.PB.command.direction = 'CONTINUE';
      master.PB.command.duration = preDuration;
      PBAddSequence
   end
   
   %12 - π/2 x
   master.PB.command.description = 'Closing pi/2';
   master.PB.command.output = finalPi2Output;
   master.PB.command.direction = 'CONTINUE';
   master.PB.command.duration = extraRF + piDuration/2;
   PBAddSequence
   
   %13 - Blank buffer
   master.PB.command.description = 'Blank buffer';
   master.PB.command.output = sigref;
   master.PB.command.direction = 'CONTINUE';
   master.PB.command.duration = 1000;
   PBAddSequence
   
   if AOMBuffer > 0
      bufferOutput = 1+sigref;
   else
      bufferOutput = 2+sigref;
   end
   %14 - AOM buffer
   master.PB.command.description = 'AOM on buffer';
   master.PB.command.output = bufferOutput;
   master.PB.command.direction = 'CONTINUE';
   master.PB.command.duration = abs(AOMBuffer);
   PBAddSequence
   
   %15 - Signal
   master.PB.command.description = 'Collection';
   master.PB.command.output = 3+sigref;
   master.PB.command.direction = 'CONTINUE';
   master.PB.command.duration = collectionTime;
   PBAddSequence
   
   
   %16 - Repolarization
   master.PB.command.description = 'Repolarization';
   master.PB.command.output = 1+sigref;
   master.PB.command.direction = 'CONTINUE';
   master.PB.command.duration = 7000;
   PBAddSequence
   
end

loopTracker = [];
for ii = 1:numel(master.PB.sequence)
    switch master.PB.sequence(ii).direction
        case 'LOOP'
            loopTracker(end+1) = ii; %#ok<AGROW>
        case 'END_LOOP'
            if isempty(loopTracker)
                error('Attempted to end loop while no loop has begun')
            end
            master.PB.sequence(ii).contextinfo = loopTracker(end);
            loopTracker(end) = [];
    end
end







%% Scan modifications

%Deletes old scan
if isfield(master.gui,'scan')
   master.gui = rmfield(master.gui,'scan');
end

%Look for where pulse description contains tau and tau/2 for where to
%scan
descriptionList = squeeze(struct2cell(master.PB.sequence));
nameList = fieldnames(master.PB.sequence);
descriptionList = descriptionList(strcmp(nameList,'description'),:);
allScans = find(contains(descriptionList,'tau'));
tauScans = xor(contains(descriptionList,'tau'),contains(descriptionList,'tau/2'));
tau2Scans = contains(descriptionList,'tau/2');

if preBuffer
   pre = preDuration;
else
   pre = 0;
end
if postBuffer
   post = postDuration;
else
   post = 0;
end
master.gui.scan.addresses = allScans;
master.gui.scan.starts = [];
tauReduction = (piDuration + extraRF) + pre + post;
master.gui.scan.starts(tauScans) = startDuration - tauReduction;
master.gui.scan.ends(tauScans) = endDuration - tauReduction;

tau2Find = find(tau2Scans);
pairedLocations = tau2Find(diff(tau2Find) == 1);
pairedLocations(end+1:end+numel(pairedLocations)) = pairedLocations+1;
master.gui.scan.starts(pairedLocations) = (startDuration-tauReduction)/2;
master.gui.scan.ends(pairedLocations) = (endDuration-tauReduction)/2;

%Tau alone (start and end)
soloLocations = tau2Find(~ismember(tau2Find,pairedLocations));
master.gui.scan.starts(soloLocations) = startDuration/2 - (piDuration+extraRF)*(3/4) - post - pre-10;
master.gui.scan.ends(soloLocations) = endDuration/2 - (piDuration+extraRF)*(3/4) - post - pre-10;

master.gui.scan.starts = master.gui.scan.starts(master.gui.scan.starts ~= 0);
master.gui.scan.ends = master.gui.scan.ends(master.gui.scan.ends ~= 0);

%find tau/2 is alone (beginning and end), or together (part of singular
%tau). 
%3 different possibilities
%Tau (whole) = TauR - pi - pre - post
%Tau/2(back to back) = (TauR - pi - post - pre)/2
%Tau/2(beginning&end) = TauR/2 - 3pi/4 - post - pre

master.gui.scan.nsteps = nSteps;
master.gui.scan.stepsize = (master.gui.scan.ends-master.gui.scan.starts)./(master.gui.scan.nsteps-1);

%If editing the scan, include these lines to prevent errors
master.gui.nscans = length(master.gui.scan);
master.gui.odoplotted = ones(1,length(master.gui.scan));
master.gui.chosensteps =  ones(1,length(master.gui.scan));
master.gui.scan.stepsize = (master.gui.scan.ends-master.gui.scan.starts)./(master.gui.scan.nsteps-1);
master.gui.scan.type = 'Pulse duration';

master.gui.plotInfo.addedxOffset = tauReduction;
master.gui.plotInfo.axisPulse = 2;
%% Valid pulse sequence commands

%Output: binary sum of all active channels as given below
%1 - AOM
%2 - SPC Switch
%4 - DAQ Voltage
%8 - RF
%16 - I                  (this is an i not a 1)
%32 - Q

%Direction: what the pulse blaster will do after completing the current
%step
%CONTINUE - "default" value indicating simply going to next step
%LOOP - begins a loop. Note: the pulse with this direction is NOT included
%inside the loop. Requires context info on how many times it will loop
%END LOOP - ends a loop. Note: the pulse with this direction IS included
%inside the loop. Requires context info on which begin loop it is ending

%Duration: duration of the pulse sequence in ns. Must be greater than 7
end

