function CollectionTime(templateInputs)
%Loads a sequence and scan to analyze contrast at different collection
%times

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
   master.gui.PSE.inputNames(1) = "RF resonance frequency (0 for 2.87)";
   master.gui.PSE.inputNames(2) = "Pi duration";
   master.gui.PSE.inputNames(3) = "Duration start (0 for default)";
   master.gui.PSE.inputNames(4) = "Duration end (0 for default)";
   master.gui.PSE.inputNames(5) = "Duration n steps (0 for default)";
else
   
   %Deletes the old sequence if present. Do not change
   if isfield(master.PB,'sequence')
      master.PB = rmfield(master.PB,'sequence');
   end
   
   %% Calculations and shorthand
   
   %Shorthand notation for inputs
   chosenfreq = str2double(templateInputs{1});
   piDur = str2double(templateInputs{2});
   startdur = str2double(templateInputs{3});
   enddur = str2double(templateInputs{4});
   nsteps = str2double(templateInputs{5});
   
   %The following sets defaults for inputs if they are set to 0
   if chosenfreq == 0
      chosenfreq = 2.87;
   end
   master.RF.frequency = chosenfreq;
   %Sets RF value to resonance
   RFFrequency

   master.PB.totalLoops = 2e5;
   master.PB.addTotalLoops = true;
   
   if startdur == 0
      startdur = 500;
   end
   
   if enddur == 0
      enddur = 1500;
   end
   
   if nsteps == 0
      nsteps = 11;
   end
   
   
   
   %% Creation of the pulse sequence using custom inputs
   %Each pulse in a sequence must have an output, direction, and duration
   %as well as a contextinfo in some cases. Once these have been input,
   %running the PBAddSequence command will add a new pulse with the current
   %settings to the end of the sequence. See the end of this function for
   %information about valid values for each of these.
   
   %1 - Buffer at start of loop gives time for AOM to turn off before RF
   %pulse
   master.PB.command.output = 4;
   master.PB.command.direction = 'CONTINUE';
   master.PB.command.duration = 500; 
   PBAddSequence

   %2 - RF pulse
   master.PB.command.output = 12;
   master.PB.command.direction = 'CONTINUE';
   master.PB.command.duration = piDur; 
   PBAddSequence
   
   %3 - AOM buffer
   master.PB.command.output = 5;
   master.PB.command.direction = 'CONTINUE';
   master.PB.command.duration = 300; 
   PBAddSequence
   
   %4 - Variable signal data collection
   master.PB.command.output = 7;
   master.PB.command.direction = 'CONTINUE';
   master.PB.command.duration = 500; %Overwritten by scan
   PBAddSequence
   
   %5 - Repolarization
   master.PB.command.output = 5;
   master.PB.command.direction = 'CONTINUE';
   master.PB.command.duration = 7000; 
   PBAddSequence
   
   %6 - DAQ voltage buffer
   master.PB.command.output = 1;
   master.PB.command.direction = 'CONTINUE';
   master.PB.command.duration = 500; 
   PBAddSequence
   
   %7 - Variable reference data collection
   master.PB.command.output = 3;
   master.PB.command.direction = 'CONTINUE';
   master.PB.command.duration = 500; %Overwritten by scan
   PBAddSequence
   
   %8 - "Repolarization" to keep symmetry
   master.PB.command.output = 1;
   master.PB.command.direction = 'CONTINUE';
   master.PB.command.duration = 7000; 
   PBAddSequence
  
   
   %% Scan modifications

   %Deletes old scan
   if isfield(master.gui,'scan')
      master.gui = rmfield(master.gui,'scan');
   end
   
   %Modify scan to incorporate input values
   master.gui.scan.addresses = [4 7];%Addresses that will be overwritten
   master.gui.scan.starts = [startdur startdur];%Starting value for each address respectively
   master.gui.scan.ends = [enddur enddur];%Ending value for each address respectively
   master.gui.scan.nsteps = nsteps;%Number of steps scan has
   
   %If editing the scan, include these lines to prevent errors
   master.gui.nscans = length(master.gui.scan);
   master.gui.odoplotted = ones(1,length(master.gui.scan));
   master.gui.chosensteps =  ones(1,length(master.gui.scan));
   master.gui.scan.stepsize = (master.gui.scan.ends-master.gui.scan.starts)./(master.gui.scan.nsteps-1);
   master.gui.scan.type = 'Pulse duration';

end
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

