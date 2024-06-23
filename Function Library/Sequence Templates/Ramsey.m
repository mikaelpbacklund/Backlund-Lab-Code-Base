function Ramsey(templateInputs)
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
   master.gui.PSE.inputNames(1) = "RF resonance frequency";
   master.gui.PSE.inputNames(2) = "Collection time (0 for default)";
   master.gui.PSE.inputNames(3) = "π (real)"; 
   master.gui.PSE.inputNames(4) = "τ start (0 for default)";
   master.gui.PSE.inputNames(5) = "τ end (0 for default)";
   master.gui.PSE.inputNames(6) = "τ n steps (0 for default)";
   master.gui.PSE.inputNames(7) = "RF duration reduction";
   master.gui.PSE.inputNames(8) = "AOM buffer";
else
   
   %Deletes the old sequence if present. Do not change
   if isfield(master.PB,'sequence')
      master.PB = rmfield(master.PB,'sequence');
   end
   
   %% Calculations and shorthand
   
   %Shorthand notation for inputs
   master.RF.frequency = str2double(templateInputs{1});
   collectt = str2double(templateInputs{2});
   piDur = str2double(templateInputs{3});
   startdur = str2double(templateInputs{4});
   enddur = str2double(templateInputs{5});
   nsteps = str2double(templateInputs{6});
   extraRF = str2double(templateInputs{7});
   aomBuffer = str2double(templateInputs{8});
   
   %Sets RF value to resonance
   if isfield(master.RF,'initialized')
      if master.RF.initialized
         RFFrequency
      end
   end

   master.PB.totalLoops = 5e4;
   master.PB.addTotalLoops = true;
   
   %The following sets defaults for inputs if they are set to 0
   if startdur == 0
      startdur = 10;
   end
   
   if enddur == 0
      enddur = 500;
   end
   
   if nsteps == 0
      nsteps = 50;
   end   
   
   
   %% Creation of the pulse sequence using custom inputs
   %Each pulse in a sequence must have an output, direction, and duration
   %as well as a contextinfo in some cases. Once these have been input,
   %running the PBAddSequence command will add a new pulse with the current
   %settings to the end of the sequence. See the end of this function for
   %information about valid values for each of these.
   
   if master.NIDAQ.confocal
      sigref = 4;
   else
      sigref = 0;
      %0.1 - WF reference pulse
      master.PB.command.description = 'WF reference';
      master.PB.command.output = 4;
      master.PB.command.direction = 'CONTINUE';
      master.PB.command.duration = 25;
      PBAddSequence

      %0.2 - WF compensation
      master.PB.command.description = 'WF compensation for sig/ref';
      master.PB.command.output = 0;
      master.PB.command.direction = 'CONTINUE';
      master.PB.command.duration = 50;
      PBAddSequence
   end
   
   %1 - Buffer at start of loop equivalent to buffers for signal
   master.PB.command.description = 'AOM off buffer';
   master.PB.command.output = 0;
   master.PB.command.direction = 'CONTINUE';
   master.PB.command.duration = 2000+piDur+2*extraRF; 
   PBAddSequence

   %2 - Scanned compensation pulse for symmetry
   master.PB.command.description = 'Symmetry scanned';
   master.PB.command.output = 0;%Overwritten by scan
   master.PB.command.direction = 'CONTINUE';
   master.PB.command.duration = 100; 
   PBAddSequence
   
   %3 - AOM buffer
   master.PB.command.description = 'AOM on buffer';
   master.PB.command.output = 1;
   master.PB.command.direction = 'CONTINUE';
   master.PB.command.duration = aomBuffer; 
   PBAddSequence
   
   %4 - Reference collection
   master.PB.command.description = 'Collection (reference)';
   master.PB.command.output = 3;
   master.PB.command.direction = 'CONTINUE';
   master.PB.command.duration = collectt;
   PBAddSequence
   
   %5 - Repolarization
   master.PB.command.description = 'Repolarization';
   master.PB.command.output = 1;
   master.PB.command.direction = 'CONTINUE';
   master.PB.command.duration = 7000; 
   PBAddSequence
   
   if ~master.NIDAQ.confocal
      %5.1 - WF signal pulses
      master.PB.command.description = 'WF signal';
      master.PB.command.output = 4;
      master.PB.command.direction = 'CONTINUE';
      master.PB.command.duration = 25;
      PBAddSequence
      
      %5.1 - WF signal pulses
      master.PB.command.description = 'WF gap';
      master.PB.command.output = 0;
      master.PB.command.direction = 'CONTINUE';
      master.PB.command.duration = 25;
      PBAddSequence
      
      %5.1 - WF signal pulses
      master.PB.command.description = 'WF signal';
      master.PB.command.output = 4;
      master.PB.command.direction = 'CONTINUE';
      master.PB.command.duration = 25;
      PBAddSequence
   end
   
   %6 - Buffer for AOM before RF
   master.PB.command.description = 'AOM off buffer';
   master.PB.command.output = sigref;
   master.PB.command.direction = 'CONTINUE';
   master.PB.command.duration = 1000; 
   PBAddSequence
   
   %7 - π/2
   master.PB.command.description = 'pi/2';
   master.PB.command.output = 8 + sigref;
   master.PB.command.direction = 'CONTINUE';
   master.PB.command.duration = extraRF + piDur/2; 
   PBAddSequence
   
   %8 - τ
   master.PB.command.description = 'Scanned tau';
   master.PB.command.output = sigref;
   master.PB.command.direction = 'CONTINUE';
   master.PB.command.duration = 100; %Overwritten by scan
   PBAddSequence
   
   %9 - π/2
   master.PB.command.description = 'pi/2';
   master.PB.command.output = 8 + sigref;
   master.PB.command.direction = 'CONTINUE';
   master.PB.command.duration = extraRF + piDur/2; 
   PBAddSequence

   %10 - Buffer post RF
   master.PB.command.description = 'pi/2';
   master.PB.command.output = sigref;
   master.PB.command.direction = 'CONTINUE';
   master.PB.command.duration = 1000; 
   PBAddSequence
   
   %11 - AOM buffer
   master.PB.command.description = 'AOM on buffer';
   master.PB.command.output = 1 + sigref;
   master.PB.command.direction = 'CONTINUE';
   master.PB.command.duration = aomBuffer; 
   PBAddSequence
   
   %12 - Signal collection
   master.PB.command.description = 'Collection (signal)';
   master.PB.command.output = 3 + sigref;
   master.PB.command.direction = 'CONTINUE';
   master.PB.command.duration = collectt; 
   PBAddSequence
   
   %13 - "Repolarization"
   master.PB.command.description = 'Repolarization for symmetry';
   master.PB.command.output = 1 + sigref;
   master.PB.command.direction = 'CONTINUE';
   master.PB.command.duration = 7000; 
   PBAddSequence   
   
  
   
   %% Scan modifications
   
   %Modify scan to incorporate input values
   if master.NIDAQ.confocal
      master.gui.scan.addresses = [2 8];%Addresses that will be overwritten
   else
      master.gui.scan.addresses = [4 13];
   end
   master.gui.scan.starts = [];
   master.gui.scan.ends = [];
   master.gui.scan.starts(1:2) = startdur - extraRF;%Starting value for each address respectively
   master.gui.scan.ends(1:2) = enddur - extraRF;%Ending value for each address respectively
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

