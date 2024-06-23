function SpinEcho(templateInputs)
%Loads a spin echo pulse sequence based on the π and τ inputs

global master

%Real tau must be at least 50 + extraRF + 3pi/4

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
   master.gui.PSE.inputNames(2) = "Collection time";
   master.gui.PSE.inputNames(3) = "π (real)";
   master.gui.PSE.inputNames(4) = "τ start";
   master.gui.PSE.inputNames(5) = "τ end";
   master.gui.PSE.inputNames(6) = "τ steps";
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
   taustart = str2double(templateInputs{4});
   tauend = str2double(templateInputs{5});
   tausteps = str2double(templateInputs{6});
   extraRF = str2double(templateInputs{7});
   AOMbuffer = str2double(templateInputs{8});
   
   %Sets RF value to resonance
   if isfield(master.RF,'initialized')
      if master.RF.initialized
         RFFrequency
      end
   end
   
   master.RF.modulationOn = true;
   master.RF.modulationType = 'I/Q';
   
   %% Creation of the pulse sequence using custom inputs
   %Each pulse in a sequence must have an output, direction, and duration
   %as well as a contextinfo in some cases. Once these have been input,
   %running the PBAddSequence command will add a new pulse with the current
   %settings to the end of the sequence. See the end of this function for
   %information about valid values for each of these.
   
   if master.NIDAQ.confocal
      sigref = 4;
   else
      %0.1 - WF reference pulses
      master.PB.command.description = 'WF reference';
      master.PB.command.output = 4;
      master.PB.command.direction = 'CONTINUE';
      master.PB.command.duration = 25;
      PBAddSequence
      sigref = 0;
   end
   
   %1 - Buffer at beginning of loop
   master.PB.command.description = 'Initial buffer';
   master.PB.command.output = 0;
   master.PB.command.direction = 'CONTINUE';
   master.PB.command.duration = 2000;
   PBAddSequence
   
   %2 - π/2 x
   master.PB.command.description = 'pi/2 x';
   master.PB.command.output = 8;
   master.PB.command.direction = 'CONTINUE';
   master.PB.command.duration = extraRF + piDur/2;
   PBAddSequence

   %3 - τ
   master.PB.command.description = 'Scanned tau';
   master.PB.command.output = 0;
   master.PB.command.direction = 'CONTINUE';
   master.PB.command.duration = 100; %Overwritten by scan
   PBAddSequence

   %4
   master.PB.command.description = 'pi y ramp up';
   master.PB.command.output = 16;
   master.PB.command.direction = 'CONTINUE';
   master.PB.command.duration = 25;
   PBAddSequence
   
   %5 - π y
   master.PB.command.description = 'pi y';
   master.PB.command.output = 24;
   master.PB.command.direction = 'CONTINUE';
   master.PB.command.duration = extraRF + piDur;
   PBAddSequence

   %6 - τ
   master.PB.command.description = 'Scanned tau';
   master.PB.command.output = 0;
   master.PB.command.direction = 'CONTINUE';
   master.PB.command.duration = 100; %Overwritten by scan
   PBAddSequence

   %7
   master.PB.command.description = 'pi/2 -x ramp up';
   master.PB.command.output = 48;
   master.PB.command.direction = 'CONTINUE';
   master.PB.command.duration = 25;
   PBAddSequence
   
   %8 - π/2 -x
   master.PB.command.description = 'pi/2 -x';
   master.PB.command.output = 56;
   master.PB.command.direction = 'CONTINUE';
   master.PB.command.duration = extraRF + piDur/2;
   PBAddSequence
   
   %9 - Blank buffer
   master.PB.command.description = 'Blank buffer';
   master.PB.command.output = 0;
   master.PB.command.direction = 'CONTINUE';
   master.PB.command.duration = 2500;
   PBAddSequence
   
    if AOMbuffer > 0
      bufferOutput = 1;
   else
      bufferOutput = 2;
   end
   %10 - AOM buffer
   master.PB.command.description = 'AOM on buffer';
   master.PB.command.output = bufferOutput;
   master.PB.command.direction = 'CONTINUE';
   master.PB.command.duration = abs(AOMbuffer); 
   PBAddSequence
   
   %11 - Reference collection
   master.PB.command.description = 'Collection (reference)';
   master.PB.command.output = 3;
   master.PB.command.direction = 'CONTINUE';
   master.PB.command.duration = collectt;
   PBAddSequence
   
   %12 - Repolarization
   master.PB.command.description = 'Repolarization';
   master.PB.command.output = 1;
   master.PB.command.direction = 'CONTINUE';
   master.PB.command.duration = 7000;
   PBAddSequence
   
   if ~master.NIDAQ.confocal
      %12.1 - WF signal pulses
      master.PB.command.description = 'WF signal';
      master.PB.command.output = 4;
      master.PB.command.direction = 'CONTINUE';
      master.PB.command.duration = 25;
      PBAddSequence
      
      %12.2 - WF signal pulses
      master.PB.command.description = 'WF gap';
      master.PB.command.output = 0;
      master.PB.command.direction = 'CONTINUE';
      master.PB.command.duration = 25;
      PBAddSequence
      
      %12.3 - WF signal pulses
      master.PB.command.description = 'WF signal';
      master.PB.command.output = 4;
      master.PB.command.direction = 'CONTINUE';
      master.PB.command.duration = 25;
      PBAddSequence
   end
   
   %13 - Initial buffer
   master.PB.command.description = 'Initial buffer';
   master.PB.command.output = 4;
   master.PB.command.direction = 'CONTINUE';
   master.PB.command.duration = 2000; 
   PBAddSequence

   %14 - π/2 x
   master.PB.command.description = 'pi/2 x';
   master.PB.command.output = 12;
   master.PB.command.direction = 'CONTINUE';
   master.PB.command.duration = extraRF + piDur/2;
   PBAddSequence
   
   %15 - τ
   master.PB.command.description = 'Scanned tau';
   master.PB.command.output = 4;
   master.PB.command.direction = 'CONTINUE';
   master.PB.command.duration = 100; %Overwritten by scan
   PBAddSequence

   %16
   master.PB.command.description = 'pi y ramp up';
   master.PB.command.output = 20;
   master.PB.command.direction = 'CONTINUE';
   master.PB.command.duration = 25;
   PBAddSequence
   
   %17 - π y
   master.PB.command.description = 'pi y';
   master.PB.command.output = 28;
   master.PB.command.direction = 'CONTINUE';
   master.PB.command.duration = extraRF + piDur;
   PBAddSequence
   
   %18 - τ
   master.PB.command.description = 'Scanned tau';
   master.PB.command.output = 4;
   master.PB.command.direction = 'CONTINUE';
   master.PB.command.duration = 100; %Overwritten by scan
   PBAddSequence

   %19
   master.PB.command.description = 'pi/2 x ramp up';
   master.PB.command.output = 4;
   master.PB.command.direction = 'CONTINUE';
   master.PB.command.duration = 25;
   PBAddSequence
   
   %20 - π/2 -x
   master.PB.command.description = 'pi/2 x';
   master.PB.command.output = 12;
   master.PB.command.direction = 'CONTINUE';
   master.PB.command.duration = extraRF + piDur/2;
   PBAddSequence
   
   %21 - Blank buffer
   master.PB.command.description = 'Blank buffer';
   master.PB.command.output = sigref;
   master.PB.command.direction = 'CONTINUE';
   master.PB.command.duration = 2500;
   PBAddSequence
   
    if AOMbuffer > 0
      bufferOutput = 1+sigref;
   else
      bufferOutput = 2+sigref;
   end
   %22 - AOM buffer
   master.PB.command.description = 'AOM on buffer';
   master.PB.command.output = bufferOutput;
   master.PB.command.direction = 'CONTINUE';
   master.PB.command.duration = abs(AOMbuffer); 
   PBAddSequence
   
   %23 - Signal collection
   master.PB.command.description = 'Collection (signal)';
   master.PB.command.output = 3 + sigref;
   master.PB.command.direction = 'CONTINUE';
   master.PB.command.duration = collectt;
   PBAddSequence
   
   %24 - Repolarization
   master.PB.command.description = 'Repolarization';
   master.PB.command.output = 1 + sigref;
   master.PB.command.direction = 'CONTINUE';
   master.PB.command.duration = 7000;
   PBAddSequence

   %25
   master.PB.command.description = 'random extra time';
   master.PB.command.output = sigref;
   master.PB.command.direction = 'CONTINUE';
   master.PB.command.duration = 1000;
   PBAddSequence
   
   %% Scan modifications
   
    %Deletes old scan
   if isfield(master.gui,'scan')
      master.gui = rmfield(master.gui,'scan');
   end

   %Modify scan to incorporate input values
   if master.NIDAQ.confocal
      master.gui.scan.addresses = [3 6 15 18];%Addresses that will be overwritten
   else
      master.gui.scan.addresses = [4 7 19 22];%Addresses that will be overwritten
   end
   master.gui.scan.starts(1:4) = taustart - extraRF - 25 - (3/4)*piDur;%Starting value for each address respectively
   master.gui.scan.ends(1:4) = tauend - extraRF - 25 - (3/4)*piDur;%Ending value for each address respectively
   master.gui.scan.nsteps = tausteps;%Number of steps scan has
   
   %If editing the scan, include these lines to prevent errors
   master.gui.nscans = 1;
   master.gui.odoplotted = 1;
   master.gui.chosensteps =  1;
   master.gui.scan.stepsize = (master.gui.scan.ends-master.gui.scan.starts)./(master.gui.scan.nsteps-1);
   master.gui.scan.type = 'Pulse duration';
   master.gui.scan.scannum = '1';
   master.gui.scan.stepinput = master.gui.scan.nsteps;
   master.gui.scan.steptype = '# of points';

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

