classdef DAQ_controller < instrumentType
   %The purpose of this class is to provide a very simple end user
   %experience. Essentially everything that is done here could be
   %replicated within a script without too much difficulty, but by using
   %this class it is shorter and more readable.

   %To change ports in use, you need to disconnect the DAQ, change the
   %config, then reconnect

   properties (Dependent)
      %User editable, stored within handshake
      continuousCollection
      takeData
      activeDataChannel      
      differentiateSignal          
   end

   properties (SetAccess = {?DAQ_controller ?instrumentType}, GetAccess = public)
      %Read-only for user (derived from config), stored in properties
      manufacturer
      analogPortNames
      digitalPortNames
      counterPortNames
      daqName
      handshake
      channelInfo
      clockPort
      dataChannels   
   end

   properties (Dependent, SetAccess = {?DAQ_controller ?instrumentType}, GetAccess = public)
      %Read-only for user (derived from config), stored in handshake
      sampleRate
      toggleChannel
      signalReferenceChannel
      dataPointsTaken
      dataAcquirementMethod
   end
   
   methods   

      function h = DAQ_controller(configFileName)

          if nargin < 1
              error('Config file name required as input')
          end

         %Loads config file and checks relevant field names
         configFields = {'channelInfo','clockPort','manufacturer','identifier','sampleRate'};
         commandFields = {};
         numericalFields = {};%has units, conversion factor, and min/max         
         h = loadConfig(h,configFileName,configFields,commandFields,numericalFields);
      end
      
      function h = connect(h)  
         if h.connected
            warning('DAQ is already connected')
            return
         end

         %Suppresses a warning generated by daq code provided by matlab
         %itself in the data acquisition package. See link below for
         %information about what the warning is specifically for but know
         %it can pretty safely be ignored
         %https://www.mathworks.com/matlabcentral/answers/457222-why-do-i-receive-a-warning-about-a-value-indexed-with-no-subscripts
         warning('off','MATLAB:subscripting:noSubscriptsSpecified');
         
         %Checks if config channel labels are valid
         channels = squeeze(struct2cell(h.channelInfo));
         channels = channels(strcmp(fieldnames(h.channelInfo),'label'),:);
         
         h.dataChannels = find(contains(lower(channels),'data'));
         h.toggleChannel = find(contains(lower(channels),'toggle')  | contains(lower(channels),'enable'));
         h.signalReferenceChannel = find(contains(lower(channels),'signal') | contains(lower(channels),'reference'));
         
         if isempty(h.dataChannels)
            error('Config file must contain a channel with a label containing "data"')
         end
         if numel(h.toggleChannel) ~= 1
            error('Config file must contain exactly 1 channel with a label containing "toggle" or "enable"')
         end
         if numel(h.signalReferenceChannel) ~= 1
            error('Config file must contain exactly 1 channel with a label containing "signal" or "reference"')
         end
         
         %I hate tables and do not understand how to use them efficiently
          %Calling substructures is overly complicated to do and works in a
          %way that my brain does not accept
         a = daqlist;
         b = a.DeviceInfo;
         c = a.DeviceID;
         for ii = 1:numel(b)
            isSimulated(ii) = b(ii).IsSimulated; %#ok<AGROW>
         end
         
         %Finds the non-simulated device and stores that as the name
         h.daqName = c(~isSimulated);

         if numel(h.daqName) > 1
             error('Multiple DAQs detected')
         end
         
         %Stores list of names of ports corresponding to various types of
         %inputs
         h.analogPortNames = b(~isSimulated).Subsystems(1).ChannelNames;
         h.digitalPortNames = b(~isSimulated).Subsystems(3).ChannelNames;
         h.counterPortNames = b(~isSimulated).Subsystems(4).ChannelNames;         
         
         %Creates the connection with the DAQ itself
         h.handshake = daq(h.manufacturer);
         h.handshake.Rate = h.sampleRate;

         %Needs to be true for following functions to run
         h.connected = true;

         h.identifier = 'DAQ';
         
         %Default values
         h = setDataChannel(h,1);
         h = setContinuousCollection(h,'on');
         h = setSignalDifferentiation(h,'on');
         h.takeData = false;
         h.toggleChannel = h.defaults.toggleChannel;
         h.signalReferenceChannel = h.defaults.signalReferenceChannel;  

         %Sets the function that is triggered whenever the DAQ has the
         %amount of scans set by ScansAvailableFcnCount. This is how data
         %is read off the DAQ
         h.handshake.ScansAvailableFcn = @storeData;
         
         %Add each channel based on config info
         for ii = 1:numel(h.channelInfo)
            h = addChannel(h,h.channelInfo(ii));    
         end 
         
         addclock(h.handshake,'ScanClock','External',strcat(h.daqName,'/',h.clockPort))
         
         function handshake = storeData(handshake,evt) %#ok<INUSD> 
             % warnError = warning('error', 'MATLAB:DELETE:Permission');%Turns warning into error such that it can be caught
             try
            %User data is 2 cell array. First cell is a 1x2 matrix for
            %signal and reference. The second cell is a structure that
            %contains information about the data channel, signal reference
            %channel, and differentiating signal and reference as well as
            %whether data should be taken at all
            collectionInfo = handshake.UserData;%Shorthand
            %Reduce number of scans available by 1 to recover from indexing
            %errors caused by NI code. I cannot fix this at the source so
            %it is necessary to fix the symptoms instead
            scansAvailable = handshake.NumScansAvailable - 5;
            if scansAvailable > handshake.ScansAvailableFcnCount * 100
                [~] = read(handshake,scansAvailable,"OutputFormat","Matrix"); 
                return
            end
            
            %If no data channel has been designated, or if data collection
            %has been disabled, or if no S/R channel has been designated
            %while differentiation of S/R is enabled, stop this function
            if ~collectionInfo.takeData || isempty(collectionInfo.dataChannelNumber) || isempty(collectionInfo.toggleChannel)...
                  || (isempty(collectionInfo.signalReferenceChannel) && collectionInfo.differentiateSignal) || scansAvailable < 5
                return
            end
            
            %Read off the data from the device in matrix form
            unsortedData = read(handshake,scansAvailable,"OutputFormat","Matrix");             
            
            if strcmpi(collectionInfo.dataType,'EdgeCount')
               %Take difference between each data point and the prior one.
               %This is what is used to actually measure count increases
                counterDifference = diff(unsortedData(:,collectionInfo.dataChannelNumber));                
                
                %Create logical vector corresponding to whether a
                %difference should be counted or not
                dataOn = unsortedData(2:end,collectionInfo.toggleChannel);
                
               if ~collectionInfo.differentiateSignal
                  sig = 0;
                  ref = sum(counterDifference(dataOn));%All data put into reference
               else
                  %Determine whether data should be signal or reference
                  %like what was done with dataOn. Then put all count
                  %increases corresponding to the signal channel being on
                  %into signal, and data where the signal channel is off in
                  %reference
                  signalOn = unsortedData(2:end,collectionInfo.signalReferenceChannel);
                  sig = sum(counterDifference(signalOn & dataOn));
                  ref = sum(counterDifference(~signalOn & dataOn));
               end
               handshake.UserData.currentCounts = unsortedData(end,collectionInfo.dataChannelNumber);
               if ref < 0 || sig < 0
                   assignin("base","rawDataFromDAQ",unsortedData)
                   warning('Negative counts obtained, discarding data')
                   ref = 0;
                   sig = 0;
               end
            else%Voltage
               dataOn = unsortedData(:,collectionInfo.toggleChannel);               
               if any(dataOn)
%                    assignin('base','unsortedData',unsortedData)
                   if ~collectionInfo.differentiateSignal
                       %No signal/reference differentiation
                       ref = sum(unsortedData(dataOn,collectionInfo.dataChannelNumber));
                       sig = 0;
                   else
                       signalOn = unsortedData(:,collectionInfo.signalReferenceChannel);
                       sig = sum(unsortedData(dataOn & signalOn,collectionInfo.dataChannelNumber));
                       ref = sum(unsortedData(dataOn & ~signalOn,collectionInfo.dataChannelNumber));
                   end
               else
                   sig = 0;
                   ref = 0;
               end
               
                
            end
            
            %Add to previous values for reference and signal
            handshake.UserData.reference = handshake.UserData.reference + ref;
            handshake.UserData.signal = handshake.UserData.signal + sig;

            if ref ~= 0 %only relevant if data was obtained
            %Increase number of data points taken. Used primarily for
            %analog to find average voltage
            handshake.UserData.nPoints = handshake.UserData.nPoints + sum(dataOn);
            elseif ~isfield(handshake.UserData,'nPoints')
                handshake.UserData.nPoints = 0;
            end

             catch ME
                 if ~isfield(handshake.UserData,'numErrors')
                     handshake.UserData.numErrors = 1;
                 else
                    handshake.UserData.numErrors = handshake.UserData.numErrors+1;
                 end
                 rethrow(ME)
             end

             % warning(warnError);%Returns warning to not being error

         end

      end
      
      function h = disconnect(h)

         if ~h.connected    
             return;   
         end
         if ~isempty(h.handshake)
            h.handshake = [];
         end
         h.connected = false;
      end
      
      function h = addChannel(h,channelInfo)
         mustContainField(channelInfo,{'dataType','port'})
         %Set data type and valid port names based on input type
         switch lower(channelInfo.dataType)
            case {'v','voltage','analog'}
               dataType = 'Voltage';
               portNames = 'analogPortNames';
            case {'counter','cntr','count','edge','edge count','edgecount'}
               dataType = 'EdgeCount';
               portNames = 'counterPortNames';
            case {'digital','binary'}
               dataType = 'Digital';
               portNames = 'digitalPortNames';
            otherwise
               error('Invalid dataType for channel %d. Must be "voltage", "counter", or "digital"',ii)
         end
         
         if ~any(strcmp(channelInfo.port,h.(portNames)))
            error('Invalid port name. See %s for valid names',portNames)
         end

         %Loads the indicated channel
         addinput(h.handshake,h.daqName,channelInfo.port,dataType)
         h.handshake.UserData.dataType = dataType;
      end
      
      function h = setDataChannel(h,channelDesignation)
         %Sets active data channel number/name based on designation given.
         %Designation can be any part of the channel number, the channel
         %port, or channel label so long as it is unique to that channel
         
         %Number input
         if isa(channelDesignation,'double')
            if channelDesignation > numel(h.channelInfo)
               error('%d is greater than the %d channels',channelDesignation,numel(h.channelInfo))
            end
            h.handshake.UserData.dataChannelNumber = channelDesignation;
            h.activeDataChannel = h.channelInfo(channelDesignation).label;
            return
         end
         
         %Label/port input
         channels = squeeze(struct2cell(h.channelInfo));
         labels = channels(strcmp(fieldnames(h.channelInfo),'label'),:);
         ports = channels(strcmp(fieldnames(h.channelInfo),'port'),:);
         channelNumber = find(contains(lower(labels),lower(channelDesignation)) | contains(lower(ports),lower(channelDesignation)));
         if numel(channelNumber) ~= 1
            error("%s is an invalid channel designation. A designation must correspond to exactly 1 channel's port or label",channelDesignation)
         end
         h.activeDataChannel = h.channelInfo(channelNumber).label;
         h.handshake.UserData.dataChannelNumber = channelNumber;
         switch lower(h.channelInfo(channelNumber).dataType)
            case {'v','voltage','analog'}
               dataType = 'Voltage';
            case {'counter','cntr','count','edge','edge count','edgecount'}
               dataType = 'EdgeCount';
            case {'digital','binary'}
               dataType = 'Digital';
         end
         h.handshake.UserData.dataType = dataType;
      end
      
      function h = setSignalDifferentiation(h,onOff)
         %Enables or disables signal/reference differentiation
         h.differentiateSignal = instrumentType.discernOnOff(onOff);
         if strcmp(h.differentiateSignal,'on')
            h.handshake.UserData.differentiateSignal = true;
            h.continuousCollection = 'on';
         else
            h.handshake.UserData.differentiateSignal = false;
         end
      end

      function h = setContinuousCollection(h,onOff)
         %Sets continuous collection on or off
         checkConnection(h)
         
         h.continuousCollection = instrumentType.discernOnOff(onOff);
      end
      
      function h = resetDAQ(h)
         %Always reset the counters for the DAQ. This is fine for both
         %continuous and discrete operation. Discrete prepares DAQ for
         %taking data; continuous resets counter to prevent massive number
         %accumulation         
         
         %If the DAQ is continuously gathering data (signal vs reference is
         %enabled AND/OR continuous is hard set) 
         if strcmp(h.continuousCollection,'on') || strcmp(instrumentType.discernOnOff(h.handshake.UserData.differentiateSignal),'on')
            %Set the reference and signal to 0
            h.handshake.UserData.reference = 0;
            h.handshake.UserData.signal = 0;
            h.handshake.UserData.nPoints = 0;
            h.handshake.UserData.currentCounts = 0;   
            %Turn on collection
            if ~h.handshake.Running, start(h.handshake,"continuous"), end     
         else
            if h.handshake.Running, stop(h.handshake), end
            resetcounters(h.handshake)
         end

      end
      
      function varargout = readDAQData(h)
         if strcmp(h.differentiateSignal,'on')
            varargout{1} = h.handshake.UserData.reference;
            varargout{2} = h.handshake.UserData.signal;
         elseif strcmp(h.continuousCollection,'on')
            varargout{1} = h.handshake.UserData.reference;
         else
            if h.handshake.Running,   stop(h.handshake), end
            unsortedData = read(h.handshake,"OutputFormat","Matrix");
            varargout{1} = unsortedData(h.handshake.UserData.dataChannelNumber);
         end
      end
      
   end

   methods
      function h = setParameter(h,val,varName)         
         if h.connected
            h.handshake.UserData.(varName) = val;
         else
            h.presets.(varName) = val;
         end
      end
      function val = getParameter(h,varName)
         if h.connected
            val =  h.handshake.UserData.(varName);
         elseif isfield(h.presets,varName) && ~isempty(h.presets.(varName))
            val = h.presets.(varName);
         elseif isfield(h.defaults,varName) && ~isempty(h.defaults.(varName))
            val = h.defaults.(varName);
         else
            val  =[];
         end
      end      

      function set.continuousCollection(h,val)
         h = setParameter(h,instrumentType.discernOnOff(val),'continuousCollection');
         if strcmpi(instrumentType.discernOnOff(val),'off')
             h = setParameter(h,'off','differentiateSignal');%#ok<NASGU>
         end
      end
      function val = get.continuousCollection(h)
         val = getParameter(h,'continuousCollection');
      end

      function set.takeData(h,val)
         h = setParameter(h,val,'takeData'); %#ok<NASGU>
      end
      function val = get.takeData(h)
         val = getParameter(h,'takeData');
      end

      function set.differentiateSignal(h,val)
         h = setParameter(h,instrumentType.discernOnOff(val),'differentiateSignal');
         if strcmpi(instrumentType.discernOnOff(val),'on')
             h = setParameter(h,'on','continuousCollection');%#ok<NASGU>
         end
      end
      function val = get.differentiateSignal(h)
         val = getParameter(h,'differentiateSignal');
      end

      function set.activeDataChannel(h,val)
         %Sets active data channel number/name based on designation given.
         %Designation can be the channel
         %port or channel label so long as it is unique to that channel

         if ~h.connected
            h.presets.activeDataChannel = val;
            return
         end
         
         %Label/port input
         channels = squeeze(struct2cell(h.channelInfo));
         labels = channels(strcmp(fieldnames(h.channelInfo),'label'),:);
         ports = channels(strcmp(fieldnames(h.channelInfo),'port'),:);
         channelNumber = find(contains(lower(labels),lower(val)) | contains(lower(ports),lower(val)));
         if numel(channelNumber) ~= 1
            error("%s is an invalid channel designation. A designation must correspond to exactly 1 channel's port or label",val)
         end
         h.handshake.UserData.dataChannelNumber = channelNumber;
         switch lower(h.channelInfo(channelNumber).dataType)
            case {'v','voltage','analog'}
               dataType = 'Voltage';
            case {'counter','cntr','count','edge','edge count','edgecount'}
               dataType = 'EdgeCount';
            case {'digital','binary'}
               dataType = 'Digital';
         end
         h.handshake.UserData.dataType = dataType;
      end
      function val = get.activeDataChannel(h)
         val = h.channelInfo(getParameter(h,'dataChannelNumber')).label;
      end

      %Properties below are read-only 
      function set.toggleChannel(h,val)
         if ~h.connected
            h.presets.toggleChannel = val;
            return
         end
         
         %Label/port input
         channels = squeeze(struct2cell(h.channelInfo));
         labels = channels(strcmp(fieldnames(h.channelInfo),'label'),:);
         ports = channels(strcmp(fieldnames(h.channelInfo),'port'),:);
         channelNumber = find(contains(lower(labels),lower(val)) | contains(lower(ports),lower(val)));
         if numel(channelNumber) ~= 1
            error("%s is an invalid channel designation. A designation must correspond to exactly 1 channel's port or label",val)
         end
         h.handshake.UserData.toggleChannel = channelNumber;
      end
      function val = get.toggleChannel(h)
         val = getParameter(h,'toggleChannel');
      end

      function set.signalReferenceChannel(h,val)
         if ~h.connected
            h.presets.signalReferenceChannel = val;
            return
         end
         
         %Label/port input
         channels = squeeze(struct2cell(h.channelInfo));
         labels = channels(strcmp(fieldnames(h.channelInfo),'label'),:);
         ports = channels(strcmp(fieldnames(h.channelInfo),'port'),:);
         channelNumber = find(contains(lower(labels),lower(val)) | contains(lower(ports),lower(val)));
         if numel(channelNumber) ~= 1
            error("%s is an invalid channel designation. A designation must correspond to exactly 1 channel's port or label",val)
         end
         h.handshake.UserData.signalReferenceChannel = channelNumber;
      end
      function val = get.signalReferenceChannel(h)
         val = getParameter(h,'signalReferenceChannel');
      end

      function set.sampleRate(h,val)
         if h.connected
            h.handshake.Rate = val;
         else
            h.presets.sampleRate = val;
         end
      end
      function val = get.sampleRate(h)
         varName = 'sampleRate';
         if h.connected
            val =  h.handshake.Rate;
         elseif isfield(h.presets,varName) && ~isempty(h.presets.(varName))
            val = h.presets.(varName);
         elseif isfield(h.defaults,varName) && ~isempty(h.defaults.(varName))
            val = h.defaults.(varName);
         else
            val  =[];
         end
      end

      function val = get.dataPointsTaken(h)
         val = getParameter(h,'nPoints');
      end

      function val = get.dataAcquirementMethod(h)
         val = getParameter(h,'dataType');
      end      

   end

end