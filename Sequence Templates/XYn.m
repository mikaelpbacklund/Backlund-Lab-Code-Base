function XYn(templateInputs)
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
   master.gui.PSE.inputNames(2) = "Collection time*";
   master.gui.PSE.inputNames(3) = "τ start";
   master.gui.PSE.inputNames(4) = "τ end";
   master.gui.PSE.inputNames(5) = "τ m steps";
   master.gui.PSE.inputNames(6) = "n XY";
   master.gui.PSE.inputNames(7) = "r sets of XYn";
   master.gui.PSE.inputNames(8) = "π (real)";
   master.gui.PSE.inputNames(9) = "RF duration reduction*";
   master.gui.PSE.inputNames(10) = "AOM buffer duration*";
   
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
   nXY = str2double(templateInputs{6});
   rsets = str2double(templateInputs{7});
   piDur = str2double(templateInputs{8});
   extraRF = str2double(templateInputs{9});
   AOMbuffer = str2double(templateInputs{10});
   
   
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
   
   %Signal vs Reference loop
   for jj  = 1:2
      
      %1 - Buffer at start of loop gives time for AOM to turn off before RF
      %pulse
      master.PB.command.description = 'AOM buffer';
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
      
      %2 - π/2 x
      master.PB.command.description = 'Initial pi/2 x';
      master.PB.command.output = 8;
      master.PB.command.direction = 'CONTINUE';
      master.PB.command.duration = extraRF + piDur/2;
      PBAddSequence
      
      for kk = 1:rsets
         for ii = 1:nXY/4
            
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
               master.PB.command.description = 'Scanned initial tau/2';
               master.PB.command.output = firstprep;
               master.PB.command.direction = 'CONTINUE';
               master.PB.command.duration = 50; %Overwritten by scan
               PBAddSequence
            else
               %3 - τ first
               master.PB.command.description = 'Scanned first tau';
               master.PB.command.output = firstprep;
               master.PB.command.direction = 'CONTINUE';
               master.PB.command.duration = 100; %Overwritten by scan
               PBAddSequence
            end
            
            %4 - π first
            master.PB.command.description = 'first pi';
            master.PB.command.output = firstpulse;
            master.PB.command.direction = 'CONTINUE';
            master.PB.command.duration = extraRF + piDur;
            PBAddSequence
            
            %5 - τ second
            master.PB.command.description = 'Scanned second tau';
            master.PB.command.output = secondprep;
            master.PB.command.direction = 'CONTINUE';
            master.PB.command.duration = 100; %Overwritten by scan
            PBAddSequence
            
            %6 - π second
            master.PB.command.description = 'Second pi';
            master.PB.command.output = secondpulse;
            master.PB.command.direction = 'CONTINUE';
            master.PB.command.duration = extraRF + piDur;
            PBAddSequence
            
            %7 - τ first
            master.PB.command.description = 'Scanned third tau';
            master.PB.command.output = firstprep;
            master.PB.command.direction = 'CONTINUE';
            master.PB.command.duration = 100; %Overwritten by scan
            PBAddSequence
            
            %8 - π first
            master.PB.command.description = 'Third pi';
            master.PB.command.output = firstpulse;
            master.PB.command.direction = 'CONTINUE';
            master.PB.command.duration = extraRF + piDur;
            PBAddSequence
            
            %9 - τ second
            master.PB.command.description = 'Scanned fourth tau';
            master.PB.command.output = secondprep;
            master.PB.command.direction = 'CONTINUE';
            master.PB.command.duration = 100; %Overwritten by scan
            PBAddSequence
            
            %10 - π second
            master.PB.command.description = 'Fourth pi';
            master.PB.command.output = secondpulse;
            master.PB.command.direction = 'CONTINUE';
            master.PB.command.duration = extraRF +  piDur;
            PBAddSequence
            
         end
      end
   
   if jj == 1
      if master.NIDAQ.confocal
         sigref = 4;
      else
         sigref = 0;
      end
      taunum = 0;
      pinum = 8;
   else
      sigref = 0;
      taunum = 48;
      pinum = 56;
   end
   
   %11 - τ/2
   master.PB.command.description = 'Scanned closing tau/2';
   master.PB.command.output = taunum;
   master.PB.command.direction = 'CONTINUE';
   master.PB.command.duration = 50; %Overwritten by scan
   PBAddSequence
   
   %12 - π/2 x
   master.PB.command.description = 'Closing pi/2';
   master.PB.command.output = pinum;
   master.PB.command.direction = 'CONTINUE';
   master.PB.command.duration = extraRF + piDur/2;
   PBAddSequence
   
   %13 - Blank buffer
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
   %14 - AOM buffer
   master.PB.command.description = 'AOM on buffer';
   master.PB.command.output = bufferOutput;
   master.PB.command.direction = 'CONTINUE';
   master.PB.command.duration = abs(AOMbuffer); 
   PBAddSequence
   
   %15 - Signal
   master.PB.command.description = 'Collection';
   master.PB.command.output = 3+sigref;
   master.PB.command.direction = 'CONTINUE';
   master.PB.command.duration = collectt; 
   PBAddSequence
   
   
   %16 - Repolarization
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
   
   %Calculates addresses that correspond to τ or τ/2
   if master.NIDAQ.confocal
      addresses = 3:2:4+8*rsets*(nXY/4);
      secondaddresses = addresses(end)+8:2:addresses(end)+9+8*rsets*(nXY/4);
   else
      addresses = 6:2:6+8*rsets*(nXY/4);
      secondaddresses = addresses(end)+9:2:addresses(end)+10+8*rsets*(nXY/4);
   end
   
   %Modify scan to incorporate input values
   master.gui.scan.addresses = [addresses secondaddresses];%Addresses that will be overwritten  
   master.gui.scan.starts = [];
   master.gui.scan.ends = [];
   master.gui.scan.starts(1:numel(master.gui.scan.addresses)) = startdur - (piDur + extraRF);%Starting value for each address respectively
   master.gui.scan.starts(1) = startdur/2 - ((3*piDur/4) + extraRF);
   master.gui.scan.starts(numel(addresses):numel(addresses)+1) = startdur/2 - ((3*piDur/4) + extraRF);
   master.gui.scan.starts(end) = startdur/2 - ((3*piDur/4) + extraRF);
   master.gui.scan.ends(1:numel(master.gui.scan.addresses)) = enddur - (piDur + extraRF);%Starting value for each address respectively
   master.gui.scan.ends(1) = enddur/2 - ((3*piDur/4) + extraRF);
   master.gui.scan.ends(numel(addresses):numel(addresses)+1) = enddur/2 - ((3*piDur/4) + extraRF);
   master.gui.scan.ends(end) = enddur/2 - ((3*piDur/4) + extraRF);
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

