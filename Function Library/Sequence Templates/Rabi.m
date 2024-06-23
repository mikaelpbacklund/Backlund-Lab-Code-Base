function Rabi(templateInputs)
%Loads a Rabi sequence and scan based on given RF frequency and duration inputs

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
   master.gui.PSE.inputNames(2) = "Collection time (0 for default)";
   master.gui.PSE.inputNames(3) = "RF duration start";
   master.gui.PSE.inputNames(4) = "RF duration end";
   master.gui.PSE.inputNames(5) = "n steps";
else
   
   %Deletes the old sequence if present. Do not change
   if isfield(master.PB,'sequence')
      master.PB = rmfield(master.PB,'sequence');
   end
   
   %% Calculations and shorthand
   
   %Shorthand notation for inputs
   master.RF.frequency = str2double(templateInputs{1});
   collectt = str2double(templateInputs{2});
   startdur = str2double(templateInputs{3});
   enddur = str2double(templateInputs{4});
   nsteps = str2double(templateInputs{5});

   if collectt == 0
       collectt = 1000;
   end

   master.PB.totalLoops = 2e5;
   master.PB.addTotalLoops = true;
   
   %Sets RF value to resonance
   if isfield(master.RF,'initialized')
      if master.RF.initialized
         RFFrequency
      end
   end
   
   %% Creation of the pulse sequence using custom inputs
   %Each pulse in a sequence must have an output, direction, and duration
   %as well as a contextinfo in some cases. Once these have been input,
   %running the PBAddSequence command will add a new pulse with the current
   %settings to the end of the sequence. See the end of this function for
   %information about valid values for each of these.
   
   if master.NIDAQ.confocal
      sigref = 4;
      buffertime = 500;
   else
      sigref = 0;
      buffertime = 1000;

      %0.1 - WF signal pulses
      master.PB.command.description = 'WF signal';
      master.PB.command.output = 4;
      master.PB.command.direction = 'CONTINUE';
      master.PB.command.duration = 25;
      PBAddSequence
      
      %0.2 - WF signal pulses
      master.PB.command.description = 'WF gap';
      master.PB.command.output = 0;
      master.PB.command.direction = 'CONTINUE';
      master.PB.command.duration = 25;
      PBAddSequence
      
      %0.3 - WF signal pulses
      master.PB.command.description = 'WF signal';
      master.PB.command.output = 4;
      master.PB.command.direction = 'CONTINUE';
      master.PB.command.duration = 25;
      PBAddSequence
   end
   
   %1 - Buffer at start of loop gives time for AOM to turn off before RF
   %pulse
   master.PB.command.description = 'AOM buffer';
   master.PB.command.output = sigref;
   master.PB.command.direction = 'CONTINUE';
   master.PB.command.duration = buffertime; 
   PBAddSequence
   
   %2 - Increasing RF duration
   master.PB.command.description = 'Scanned RF duration';
   master.PB.command.output = 8 + sigref;
   master.PB.command.direction = 'CONTINUE';
   master.PB.command.duration = 10; %Overwritten by scan
   PBAddSequence
   
   %3 - AOM on to account for input delay
   master.PB.command.description = 'AOM delay';
   master.PB.command.output = 1 + sigref;
   master.PB.command.direction = 'CONTINUE';
   master.PB.command.duration = 350; 
   PBAddSequence
   
   %4 - Take signal data
   master.PB.command.description = 'Collection (signal)';
   master.PB.command.output = 3 + sigref;
   master.PB.command.direction = 'CONTINUE';
   master.PB.command.duration = collectt; 
   PBAddSequence
   
   %5 - Repolarization
   master.PB.command.description = 'Repolarization';
   master.PB.command.output = 1 + sigref;
   master.PB.command.direction = 'CONTINUE';
   master.PB.command.duration = 4000; 
   PBAddSequence
   
   if ~master.NIDAQ.confocal
      %5.1 - WF reference pulse
      master.PB.command.description = 'WF reference';
      master.PB.command.output = 5;
      master.PB.command.direction = 'CONTINUE';
      master.PB.command.duration = 25;
      PBAddSequence
   end
   
   %6 - AOM on to account for input delay
   master.PB.command.description = 'AOM delay';
   master.PB.command.output = 1;
   master.PB.command.direction = 'CONTINUE';
   master.PB.command.duration = 3000; 
   PBAddSequence
   
   %7 - Take reference data
   master.PB.command.description = 'Collection (reference)';
   master.PB.command.output = 3;
   master.PB.command.direction = 'CONTINUE';
   master.PB.command.duration = collectt; 
   PBAddSequence

   %8 - Symmetric "Repolarization"
   master.PB.command.description = 'Symmetric repolarization';
   master.PB.command.output = 1;
   master.PB.command.direction = 'CONTINUE';
   master.PB.command.duration = 7000; 
   PBAddSequence
  
   
   %% Scan modifications
   
   %Modify scan to incorporate input values
   if master.NIDAQ.confocal
      master.gui.scan.addresses = 2;%Addresses that will be overwritten
   else
      master.gui.scan.addresses = 5;%Addresses that will be overwritten
   end
   master.gui.scan.starts = startdur;%Starting value for each address respectively
   master.gui.scan.ends = enddur;%Ending value for each address respectively
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

