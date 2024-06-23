%This script performs an ODMR with stage optimization. It makes the
%connections based on config files, generates a standard ODMR pulse
%sequence, defines the stage optimization, then runs a scan and displays
%the data of that scan.

%This warning *should* be suppressed in the DAQ code but isn't for an
%unknown reason. This is not related to my code but rather the data
%acquisition toolbox code which I obviously can't change
warning('off','MATLAB:subscripting:noSubscriptsSpecified');

%% Load instruments

if ~exist('instr','var')
   %Creates objects for necessary instrument and connects to them using
   %previously generated config files
   instr{1} = RF_generator;
   instr{1} = connect(instr{1},'RF_generator_config');
   instr{1} = toggle(instr{1},'on');%RF generator on
   instr{1} = modulationToggle(instr{1},'off');%Modulation off
   instr{1} = setAmplitude(instr{1},10);%Amplitude to 10 dbm
   
   instr{2} = DAQ_controller;
   instr{2} = connect(instr{2},'NI_DAQ_config');
   instr{2} = setSignalDifferentiation(instr{2},'on');%Differentiate signal and reference
   instr{2} = setDataChannel(instr{2},'counter');%Use counter to collect data
   
   instr{3} = pulse_blaster;
   instr{3} = connect(instr{3},'pulse_blaster_config');
   
   instr{4} = stage;
   instr{4} = connect(instr{4},'PI_stage_config');
end

%Creates an empty experiment object
if ~exist('ex','var')
   ex = experiment;
end

ex = validExperimentalConfiguration(ex,instr,'pulse sequence');

%% Create pulse sequence
%instr{3} is the pulse blaster

instr{3}.nTotalLoops = 100;%Number of times entire sequence is repeated
instr{3}.userSequence = [];%Deletes whatever the current sequence is

%Adds pulses one by one
clear pulseInfo 
pulseInfo.activeChannels = {};
pulseInfo.duration = 2500;
pulseInfo.notes = 'Initial buffer';
instr{3} = addPulse(instr{3},pulseInfo);

clear pulseInfo 
pulseInfo.activeChannels = {'AOM','DAQ'};
pulseInfo.duration = 1e6;
pulseInfo.notes = 'Reference';
instr{3} = addPulse(instr{3},pulseInfo);

clear pulseInfo 
pulseInfo.activeChannels = {};
pulseInfo.duration = 2500;
pulseInfo.notes = 'Middle buffer signal off';
instr{3} = addPulse(instr{3},pulseInfo);

clear pulseInfo 
pulseInfo.activeChannels = {'Signal'};
pulseInfo.duration = 2500;
pulseInfo.notes = 'Middle buffer signal on';
instr{3} = addPulse(instr{3},pulseInfo);

clear pulseInfo 
pulseInfo.activeChannels = {'AOM','DAQ','RF','Signal'};
pulseInfo.duration = 1e6;
pulseInfo.notes = 'Signal';
instr{3} = addPulse(instr{3},pulseInfo);

clear pulseInfo 
pulseInfo.activeChannels = {'Signal'};
pulseInfo.duration = 2500;
pulseInfo.notes = 'Final buffer';
instr{3} = addPulse(instr{3},pulseInfo);

instr{3} = sendToInstrument(instr{3});

%% Stage optimization parameters

%Type of optimization*
optSequence.consecutive = true;

%Assignment of optimization sequence
% optSequence.axes = {'x','y','z'};
% optSequence.steps = {-1:.1:1,-1:.1:1,-2:.2:2};
% 
% %Alternate way to do axes/steps
% n = 1;
% optSequence.axes{n} = 'x';
% optSequence.steps{n} = -1 : 0.1 : 1;
% n = 2;
% optSequence.axes{n} = 'y';
% optSequence.steps{n} = -1 : 0.1 : 1;
% n = 3;
% optSequence.axes{n} = 'z';
% optSequence.steps{n} = -2 : 0.2 : 2;

optSequence.axes = {'Z'};
optSequence.steps = {-.5:.1:.5};

%% Create scan

ex.scan = [];

scan.bounds = [2.25 2.3];
scan.stepSize = .0025;
scan.parameter = 'frequency';
scan.instrument = 'RF_generator';
scan.notes = 'ODMR';

ex = addScans(ex,scan);

ex.forcedCollectionPauseTime = .1;

ex = validExperimentalConfiguration(ex,instr,'pulse sequence');

%% Create manual scan 

% ex.useManualSteps = true;
% ex.manualSteps = {[2 2.1 2.2 2.5 2.8 3]};
%
% scan.parameter = 'frequency';
% scan.instrument = 'RF_generator';
% scan.notes = 'ODMR';
% 
% ex = addScans(ex,scan);
%

%% Run scan, and collect and display data

nIterations = 1;

%Prepares experiment to run from scratch
%[0,0] is the value that all initial values for the data will take
%Two values are used because we are storing ref and sig
ex = resetAllData(ex,[0 0]);

for ii = 1:nIterations
   
   %Prepares scan for a fresh start while keeping data from previous
   %iterations
   [ex,instr] = resetScan(ex,instr);
   
   %Runs initial optimization. Optimization goes to highest value based on
   %output of pulse sequence; the stage movements are determined by
   %optSequence and RF is turned off
%    [ex,instrumentCells] = stageOptimization(ex,instrumentCells,'max value','pulse sequence',optSequence,'off');
%    lastOptTime = datetime;
   
   %While the odometer is not at its max value
   while ~all(ex.odometer == [ex.scan.nSteps])
      
%       if datetime-lastOptTime > duration(0,5,0)%Check if last optimization was over 5 mins ago
%          %Runs stage optimization
%          [ex,instrumentCells] = stageOptimization(ex,instrumentCells,'max value','pulse sequence',optSequence,'off');
%          
%          %Sets new time for last optimization
%          lastOptTime = datetime;
%       end

      [ex,instr] = takeNextDataPoint(ex,instr,'pulse sequence');      

      %The following section calculates the contrast then creates/updates
      %plots for the current iteration as well as the previous iterations
      %and the average
      plotTypes = {'current','average','previous'};
      for plotName = plotTypes
         c = findContrast(ex,plotName{1});
         ex = make1DPlot(ex,c,plotName{1});
      end
      refData = cell2mat(cellfun(@(x)x(1),ex.data.current,'UniformOutput',false));
      ex = make1DPlot(ex,refData,'reference');
      
   end
   
end

%Stops continuous collection from DAQ
stop(instr{2}.handshake)

%% Run Experiment No Comments (19 lines of real code)
% nIterations = 4;
% ex = resetAllData(ex,[0 0]);
% 
% for ii = 1:nIterations
%    [ex,instr] = resetScan(ex,instr);   
%    [ex,instr] = stageOptimization(ex,instr,'max value','pulse sequence',optSequence,'off');
%    lastOptTime = datetime;
%    
%    while ~all(ex.odometer == [ex.scan.nSteps])
%       
%       if datetime-lastOptTime > duration(0,5,0)
%          [ex,instr] = stageOptimization(ex,instr,'max value','pulse sequence',optSequence,'off');
%          lastOptTime = datetime;
%       end
%       
%       [ex,instr] = takeNextDataPoint(ex,instr,'pulse sequence');      
%       
%       plotTypes = {'current'};
%       for plotName = plotTypes
%          c = findContrast(ex,plotName{1});
%          ex = make1DPlot(ex,c,plotName{1});
%       end
%       
%    end
%    
% end
% stop(instr{2}.handshake)










