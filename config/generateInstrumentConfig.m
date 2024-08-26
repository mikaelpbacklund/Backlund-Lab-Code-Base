%Creates instrument config file

%% SRS RF Generator
clear config

config.connectionInfo.vendor = 'srs';
config.connectionInfo.fieldToCheck = 'Vendor';
config.connectionInfo.checkedValue = 'Stanford';

%Commands section for what messages should be sent to the instrument
config.commands.toggleOn = 'ENBR 1';
config.commands.toggleOff = 'ENBR 0';
config.commands.toggleQuery = 'ENBR?';
config.commands.amplitude = 'AMPR %g';
config.commands.amplitudeQuery = 'AMPR?';
config.commands.frequency = 'FREQ %g MHz';
config.commands.frequencyQuery = 'FREQ? MHz';
config.commands.modulationToggleOn = 'MODL 1';
config.commands.modulationToggleOff = 'MODL 0';
config.commands.modulationToggleQuery = 'MODL?';
config.commands.modulationWaveform = 'MFNC %d';
config.commands.modulationWaveformQuery = 'MFNC?';
config.commands.modulationType = 'TYPE %d';
config.commands.modulationTypeQuery = 'TYPE?';
config.commands.modulationExternalIQ = 'QFNC 5';

%Numerical values. Each has a conversion factor, units, min and max. This
%is all saved under config.attributeInfo 
attributeName = 'frequency';
p = strcat(attributeName,'Info');
config.(p).conversionFactor = 1e3;%MHz (instrument) to GHz (user)
config.(p).units = 'GHz';
config.(p).minimum = .00095;
config.(p).maximum = 4;
config.(p).tolerance = .00001;

attributeName = 'amplitude';
p = strcat(attributeName,'Info');
config.(p).conversionFactor = 1;
config.(p).units = 'dBm';
config.(p).minimum = -110;
config.(p).maximum = 16.5;

saveLocation = pwd;%Default is to save to current directory
saveName = '\SRS_RF';
save(strcat(saveLocation,saveName),'config')


%% Pulse Blaster
clear config

%Using commands to store dll information
config.commands.library = 'C:\SpinCore\SpinAPI\lib\spinapi64.dll';%Default path when loading spincore from exe
config.commands.api = 'C:\SpinCore\SpinAPI\include\spinapi.h';
config.commands.type = 'C:\SpinCore\SpinAPI\include\pulseblaster.h';
config.commands.name = 'spinapi64';

%Channel names. Formal name is what is displayed when viewing the sequence;
%acceptable names are valid names that will "point" to the formal name when
%used for adding/modifying pulses. The order in which they are listed
%corresponds to the channel order itself e.g. the first channel name
%corresponds to the first channel of the pulse blaster (called channel 0 by
%the pulse blaster because their counting starts at 0)
config.formalChannelNames{1} = 'AOM';
config.acceptableChannelNames{1} = {'aom','laser'};%Case insensitive

config.formalChannelNames{2} = 'Data';
config.acceptableChannelNames{2} = {'data','daq','nidaq'};
%data is an important acceptable name to have somewhere. It indicates where
%the data collection is happening and is necessary to determine data
%collection duration

config.formalChannelNames{3} = 'Signal';
config.acceptableChannelNames{3} = {'s/r','sr','signal','signal/reference','signal reference','sig','sig/ref'};

config.formalChannelNames{4} = 'RF';
config.acceptableChannelNames{4} = {'rf','mw'};

config.formalChannelNames{5} = 'I';
config.acceptableChannelNames{5} = {'i','i switch'};

config.formalChannelNames{6} = 'Q';
config.acceptableChannelNames{6} = {'q','q switch'};

%Sensitive to order. Continue must be first, followed by stop, start loop,
%then end loop
config.formalDirectionNames{1} = 'Continue';
config.acceptableDirectionNames{1} = {'continue','proceed','go','nothing','standard','normal'};

config.formalDirectionNames{2} = 'Stop';
config.acceptableDirectionNames{2} = {'stop'};

config.formalDirectionNames{3} = 'Start Loop';
config.acceptableDirectionNames{3} = {'loop','startloop','start_loop','start','start loop'};

config.formalDirectionNames{4} = 'End Loop';
config.acceptableDirectionNames{4} = {'endloop','end_loop','end','end loop'};

config.clockSpeed = 500;%MHz
config.units = 'nanoseconds';
config.defaults.useTotalLoop = true;%Encompass the entire sequence in a loop
config.defaults.nTotalLoops = 1;%How many loops the above should run for
config.defaults.sendUponAddition = false;%Send sequence to pulse blaster when running addPulse

saveLocation = pwd;%Default is to save to current directory
saveName = '\pulse_blaster_config';
save(strcat(saveLocation,saveName),'config')

%% NI_DAQ

clear config

%Info about what ports correspond to what inputs
config.channelInfo(1).dataType = 'Counter';
config.channelInfo(1).port = 'ctr2';
config.channelInfo(1).label = 'Data counter';%Data must be included

config.channelInfo(2).dataType = 'Analog';
config.channelInfo(2).port = 'ai0';
config.channelInfo(2).label = 'Data analog';

config.channelInfo(3).dataType = 'Digital';
config.channelInfo(3).port = 'port0/line1';
config.channelInfo(3).label = 'Toggle';%Toggle must be included

config.channelInfo(4).dataType = 'Digital';
config.channelInfo(4).port = 'port0/line2';
config.channelInfo(4).label = 'Signal/Reference';%Signal and/or reference must be included

config.channelInfo(5).dataType = 'Digital';
config.channelInfo(5).port = 'port0/line3';
config.channelInfo(5).label = 'Testing';%Signal and/or reference must be included

%Port the clock is connected to
config.clockPort = 'PFI12';

%DAQ manufacturer
config.manufacturer = 'ni';

config.sampleRate = 1.25e6;

config.defaults.continuousCollection = false;
config.defaults.takeData = false;
config.defaults.activeDataChannel = 'Data counter';
config.defaults.differentiateSignal = false;
config.defaults.toggleChannel = 'Toggle';
config.defaults.signalReferenceChannel = 'Signal/Reference';

saveLocation = pwd;%Default is to save to current directory
saveName = '\NI_DAQ';
save(strcat(saveLocation,saveName),'config')

%% Stage

%Note: if only a single connection is used for an axis (no coarse/fine
%distinction), the connection should be designated "fine"
clear config

n = 1;
config.controllerInfo(n).model = 'C-867';
config.controllerInfo(n).grain = 'Coarse';%Fine moved first then coarse moved if fine cannot cover distance
config.controllerInfo(n).axis = 'X';
config.controllerInfo(n).internalAxisNumber = '1';%From controller
config.controllerInfo(n).invertLocation = true;%Location must be swapped when comparing with other axes
config.controllerInfo(n).conversionFactor = 1000;%mm (Instrument) to μm (User)

n = 2;
config.controllerInfo(n).model = 'C-867';
config.controllerInfo(n).grain = 'Coarse';
config.controllerInfo(n).axis = 'Y';
config.controllerInfo(n).internalAxisNumber = '2';
config.controllerInfo(n).invertLocation = true;
config.controllerInfo(n).conversionFactor = 1000;

n = 3;
config.controllerInfo(n).model = 'C-863';
config.controllerInfo(n).grain = 'Coarse';
config.controllerInfo(n).axis = 'Z';
config.controllerInfo(n).internalAxisNumber = '1';
config.controllerInfo(n).invertLocation = false;
config.controllerInfo(n).conversionFactor = 1000;

n = 4;
config.controllerInfo(n).model = 'E-727';
config.controllerInfo(n).grain = 'Fine';
config.controllerInfo(n).axis = 'X';
config.controllerInfo(n).internalAxisNumber = '1';
config.controllerInfo(n).invertLocation = false;
config.controllerInfo(n).conversionFactor = 1;

n = 5;
config.controllerInfo(n).model = 'E-727';
config.controllerInfo(n).grain = 'Fine';
config.controllerInfo(n).axis = 'Y';
config.controllerInfo(n).internalAxisNumber = '2';
config.controllerInfo(n).invertLocation = false;
config.controllerInfo(n).conversionFactor = 1;

n = 6;
config.controllerInfo(n).model = 'E-727';
config.controllerInfo(n).grain = 'Fine';
config.controllerInfo(n).axis = 'Z';
config.controllerInfo(n).internalAxisNumber = '3';
config.controllerInfo(n).invertLocation = false;
config.controllerInfo(n).conversionFactor = 1;

config.defaults.ignoreWait = false;
config.defaults.tolerance = .05;
config.defaults.pauseTime = .05;
config.defaults.resetToMidpoint = true;
config.defaults.maxRecord = 1000;
config.defaults.maxConnectionAttempts = 3;

saveLocation = pwd;%Default is to save to current directory
saveName = '\PI_stage_config';
save(strcat(saveLocation,saveName),'config')

%% 488 nm Coherent Laser

clear config

config.baudrate = 19200;
config.realReplyNumber = 2;
config.pauseTime = 2;
config.powerConversionFactor = 1;
config.discardInitialResponse = false;
config.commands.toggleQuery = "?l";
config.commands.toggleOn = "l=1";
config.commands.toggleOff = "l=0";
config.commands.setPowerQuery = "?SP";
config.commands.setPower = "P=%g";
config.commands.actualPowerQuery = "?P";

saveLocation = pwd;%Default is to save to current directory
saveName = '\laser_488';
save(strcat(saveLocation,saveName),'config')

%% 561 nm Coherent Laser

clear config

config.baudrate = 19200;
config.realReplyNumber = 2;
config.pauseTime = 2;
config.powerConversionFactor = 1;
config.discardInitialResponse = false;
config.commands.toggleQuery = "?l";
config.commands.toggleOn = "l=1";
config.commands.toggleOff = "l=0";
config.commands.setPowerQuery = "?SP";
config.commands.setPower = "P=%g";
config.commands.actualPowerQuery = "?P";

saveLocation = pwd;
saveName = '\laser_561';
save(strcat(saveLocation,saveName),'config')

%% 640 nm Coherent Laser
clear config

config.baudrate = 19200;
config.realReplyNumber = 1;
config.pauseTime = 3;
config.powerConversionFactor = 1e-3;
config.commands.toggleQuery = "source:am:state?";
config.commands.toggleOn = "source:am:state ON";
config.commands.toggleOff = "source:am:state OFF";
config.commands.setPowerQuery = "source:power:level:immediate:amplitude?";
config.commands.setLaserPower = "source:power:level:immediate:amplitude %g";
config.commands.actualPowerQuery = "source:power:level?";

saveLocation = pwd;
saveName = '\laser_561';
save(strcat(saveLocation,saveName),'config')

%% 532 nm Coherent Laser
clear config


saveLocation = pwd;
saveName = '\laser_561';
save(strcat(saveLocation,saveName),'config')


%% 532 nm Lighthouse Photonics Laser
clear config

saveLocation = pwd;
saveName = '\laser_561';
save(strcat(saveLocation,saveName),'config')

%% Hamamatsu Camera
clear config

config.manufacturer = 'hamamatsu';
config.imageType = 'MONO16_2304x2304_Std';
config.defaults.defectCorrectionEnabled = 'on';
config.defaults.defectCorrectionLevel = 'standard';
config.defaults.framesPerTrigger = 100;
config.defaults.exposureTime = 0.011216705882353;
config.defaults.useBounds = true;
config.defaults.bounds = {[1,2304],[1,2304]};
config.defaults.outputFrameStack = true;

saveLocation = pwd;
saveName = '\hamm_camm_config';
save(strcat(saveLocation,saveName),'config')

%% Kinesis Motor
clear config

%You can find what namespaces are used for a given model by opening
%program files/thorlabs/kinesis/thorlabs.MotionControl.DotNet_API
config.namespaces = {
   'Thorlabs.MotionControl.DeviceManagerCLI',...
   'Thorlabs.MotionControl.GenericPiezoCLI',...
   'Thorlabs.MotionControl.KCubePiezoCLI'};

%The full class name that is used for establishing handshake
config.fullClassName = 'Thorlabs.MotionControl.KCubePiezo.CreateKCubePiezo';

%Times are in ms
config.settingsTimeout = 7e3;
config.pollTime = 250;%Time between communications between MatLab and instrument

saveLocation = pwd;
saveName = '\ddl_config';
save(strcat(saveLocation,saveName),'config')

%% Windfreak RF
clear config

config.identifier = 'WF RF';

config.connectionInfo.vendor = 'windfreak';
config.connectionInfo.comPort = 9;%Unknown com port
config.connectionInfo.baudRate = 19200;

%Commands section for what messages should be sent to the instrument
config.commands.toggleOn = 'o 1';
config.commands.toggleOff = 'o 0';
config.commands.toggleQuery = 'o?';
config.commands.amplitude = 'a %g';
config.commands.amplitudeQuery = 'w?';
config.commands.frequency = 'f %d';
config.commands.frequencyQuery = 'f?';
config.commands.modulationToggleOn = '';
config.commands.modulationToggleOff = '';
config.commands.modulationToggleQuery = '';
config.commands.modulationWaveform = '';
config.commands.modulationWaveformQuery = '';
config.commands.modulationType = '';
config.commands.modulationTypeQuery = '';
config.commands.modulationExternalIQ = '';

%Numerical values. Each has a conversion factor, units, min and max. This
%is all saved under config.attributeInfo 
attributeName = 'frequency';
p = strcat(attributeName,'Info');
config.(p).conversionFactor = 1e3;%MHz (instrument) to GHz (user)
config.(p).units = 'GHz';
config.(p).minimum = 34e-6;
config.(p).maximum = 4.4;

attributeName = 'amplitude';
p = strcat(attributeName,'Info');
config.(p).conversionFactor = 1;
config.(p).units = 'dBm';
config.(p).minimum = 0;
config.(p).maximum = 63;

saveLocation = pwd;%Default is to save to current directory
saveName = '\windfreak_RF_generator_config';
save(strcat(saveLocation,saveName),'config')

