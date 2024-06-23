function Correlation(templateInputs)
%Loads a Rabi sequence and scan based on given RF frequency and duration inputs
%Minimum τ is 80 b/c minimum τ/2 is 40 due to I/Q delay

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
   master.gui.PSE.inputNames(3) = "τcorr start";
   master.gui.PSE.inputNames(4) = "τcorr end";
   master.gui.PSE.inputNames(5) = "τcorr m steps";
   master.gui.PSE.inputNames(6) = "τ";
   master.gui.PSE.inputNames(7) = "n XY";
   master.gui.PSE.inputNames(8) = "r sets of XYn";
   master.gui.PSE.inputNames(9) = "π (real)";
   master.gui.PSE.inputNames(10) = "RF duration reduction";
   master.gui.PSE.inputNames(11) = "AOM buffer";
   
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
   tau = str2double(templateInputs{6});
   nXY = str2double(templateInputs{7});
   rsets = str2double(templateInputs{8});
   piDur = str2double(templateInputs{9});
   extraRF = str2double(templateInputs{10});
   AOMbuffer = str2double(templateInputs{11});
   
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
   
   for mm = 1:2 %Signal/Reference loop
      
      %1 - Buffer at start of loop
      master.PB.command.description = 'Initial buffer';
      master.PB.command.output = 0;
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
         
         if mm == 1
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
      
      
      %XYn
      for jj = 1:2
         
         %2 - π/2 x
         master.PB.command.description = 'Initial pi/2 x';
         master.PB.command.output = 8;
         master.PB.command.direction = 'CONTINUE';
         master.PB.command.duration = extraRF + piDur/2;
         PBAddSequence
         
         for kk = 1:rsets %total sets of XYN
            for ii = 1:nXY/4 %Total number of XY
               
               if mod(ii,2) == 1 %Odd set
                  firstprep = 16; %I is on (y)
                  firstpulse = 24; %I and RF is on (y)
                  secondprep = 0; %I is off (x)
                  secondpulse = 8; %I is off and RF is on (x)
               else %Even set
                  firstprep = 0; %I is on (x)
                  firstpulse = 8; %I and RF is on (x)
                  secondprep = 16; %I is off (y)
                  secondpulse = 24; %I is off and RF is on (y)
               end
               
               if ii == 1 && kk == 1
                  %3 - τ/2 first
                  master.PB.command.description = 'Initial tau/2';
                  master.PB.command.output = firstprep;
                  master.PB.command.direction = 'CONTINUE';
                  master.PB.command.duration = tau/2 - ((3/4)*piDur + extraRF);
                  PBAddSequence
               else
                  %3 - τ first
                  master.PB.command.description = 'First tau';
                  master.PB.command.output = firstprep;
                  master.PB.command.direction = 'CONTINUE';
                  master.PB.command.duration = tau - (piDur + extraRF);
                  PBAddSequence
               end
               
               %4 - π first
               master.PB.command.description = 'First pi';
               master.PB.command.output = firstpulse;
               master.PB.command.direction = 'CONTINUE';
               master.PB.command.duration = extraRF + piDur;
               PBAddSequence
               
               %5 - τ second
               master.PB.command.description = 'Second tau';
               master.PB.command.output = secondprep;
               master.PB.command.direction = 'CONTINUE';
               master.PB.command.duration = tau - (piDur + extraRF);
               PBAddSequence
               
               %6 - π second
               master.PB.command.description = 'Second pi';
               master.PB.command.output = secondpulse;
               master.PB.command.direction = 'CONTINUE';
               master.PB.command.duration = extraRF + piDur;
               PBAddSequence
               
               %7 - τ first
               master.PB.command.description = 'Third tau';
               master.PB.command.output = firstprep;
               master.PB.command.direction = 'CONTINUE';
               master.PB.command.duration = tau - (piDur + extraRF);
               PBAddSequence
               
               %8 - π first
               master.PB.command.description = 'Third pi';
               master.PB.command.output = firstpulse;
               master.PB.command.direction = 'CONTINUE';
               master.PB.command.duration = extraRF + piDur;
               PBAddSequence
               
               %9 - τ second
               master.PB.command.description = 'Fourth tau';
               master.PB.command.output = secondprep;
               master.PB.command.direction = 'CONTINUE';
               master.PB.command.duration = tau - (piDur + extraRF);
               PBAddSequence
               
               %10 - π second
               master.PB.command.description = 'Fourth pi';
               master.PB.command.output = secondpulse;
               master.PB.command.direction = 'CONTINUE';
               master.PB.command.duration = extraRF +  piDur;
               PBAddSequence
            end
            
         end
         
         if mm == 1 || jj == 1
            if master.NIDAQ.confocal
               sigref = 4;
            else
               sigref = 0;
            end
            taunum = 16;%0
            pinum = 24;%8
         else
            sigref = 0;
            taunum = 32;%48
            pinum = 40;%56
         end
         
         %12 - τ/2
         master.PB.command.description = 'Closing tau/2';
         master.PB.command.output = taunum;
         master.PB.command.direction = 'CONTINUE';
         master.PB.command.duration = tau/2 - ((3/4)*piDur + extraRF);
         PBAddSequence
         
         %13 - π/2
         master.PB.command.description = 'Closing pi/2';
         master.PB.command.output = pinum;
         master.PB.command.direction = 'CONTINUE';
         master.PB.command.duration = extraRF + piDur/2;
         PBAddSequence
         
         if jj == 1
            %11 - taucorr
            master.PB.command.description = 'Correlation time';
            master.PB.command.output = 0;
            master.PB.command.direction = 'CONTINUE';
            master.PB.command.duration = 5000; %Overwritten by scan
            PBAddSequence
         end
      end
      
      %14 - Blank buffer
      master.PB.command.description = 'Blank buffer';
      master.PB.command.output = sigref;
      master.PB.command.direction = 'CONTINUE';
      master.PB.command.duration = 1000;
      PBAddSequence
      
      if AOMbuffer > 0
         bufferOutput = 1+sigref;
      else
         bufferOutput = 2+sigref;
      end
      %15 - AOM buffer
      master.PB.command.description = 'AOM on buffer';
      master.PB.command.output = bufferOutput;
      master.PB.command.direction = 'CONTINUE';
      master.PB.command.duration = abs(AOMbuffer);
      PBAddSequence
      
      %16 - Signal
      master.PB.command.description = 'Collection';
      master.PB.command.output = 3+sigref;
      master.PB.command.direction = 'CONTINUE';
      master.PB.command.duration = collectt;
      PBAddSequence
      
      
      %17 - Repolarization
      master.PB.command.description = 'Repolarization';
      master.PB.command.output = 1+sigref;
      master.PB.command.direction = 'CONTINUE';
      master.PB.command.duration = 7000;
      PBAddSequence
      
      
   end
   
   %% Scan modifications
   
   %Deletes old scan
   if isfield(master.gui,'scan')
      master.gui = rmfield(master.gui,'scan');
   end
   
   regPulses = (8*rsets*(nXY/4));
   %Calculates addresses that correspond to τcorr
   if master.NIDAQ.confocal
      firstaddress = (1 + 1 + regPulses + 2 + 1);
      secondaddress = firstaddress + 1 + regPulses + 2 + 4 + 1 + 1 + regPulses + 2 + 1;
      master.gui.scan.addresses = [firstaddress secondaddress];
      master.gui.scan.starts = [startdur startdur];%Starting value for each address respectively
      master.gui.scan.ends(1:numel(master.gui.scan.addresses)) = [enddur enddur];%Starting value for each address respectively
   else
      firstaddress = (3 + 1 + 1 + regPulses + 2 + 1);
      secondaddress = firstaddress + 1 + regPulses + 2 + 4 + 1 + 1 + 1 + regPulses + 2 + 1;
      master.gui.scan.addresses = [firstaddress secondaddress];
      master.gui.scan.starts = [startdur startdur];%Starting value for each address respectively
      master.gui.scan.ends(1:numel(master.gui.scan.addresses)) = [enddur enddur];%Starting value for each address respectively
   end
   
   %Modify scan to incorporate input values
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
