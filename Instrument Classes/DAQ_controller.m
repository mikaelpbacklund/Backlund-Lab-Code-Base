classdef DAQ_controller < instrumentType
    %DAQ_controller - Controls and manages data acquisition devices
    %
    % Features:
    %   - Automatic device detection and connection
    %   - Support for analog, digital, and counter channels
    %   - Signal/reference differentiation
    %   - Continuous and discrete data collection modes
    %
    %
    % Dependencies:
    %   - MATLAB Data Acquisition Toolbox
    %   - Configuration file with channel definitions
    %
    % See also: instrumentType, daq

    %% User Configurable Properties
    properties (Dependent)
        % Properties that can be modified by the user
        % continuousCollection    % Enable/disable continuous data collection
        % takeData               % Enable/disable data collection
        % activeDataChannel      % Currently active data channel
        % differentiateSignal    % Enable/disable signal/reference differentiation
        % maxErrorCount         % Maximum number of errors before stopping
        % % Data collection configuration
        % scanBufferMultiplier  % Multiplier for buffer overflow detection
        % minScansAvailable     % Minimum number of scans required for processing
        % voltageScaleFactor    % Scale factor for voltage data conversion
        % maxDataPoints         % Maximum number of data points to store
    end

    properties
        % Properties that can be modified by the user
        continuousCollection    % Enable/disable continuous data collection
        takeData               % Enable/disable data collection
        activeDataChannel      % Currently active data channel
        differentiateSignal    % Enable/disable signal/reference differentiation
        maxErrorCount         % Maximum number of errors before stopping
        % Data collection configuration
        scanBufferMultiplier  % Multiplier for buffer overflow detection
        minScansAvailable     % Minimum number of scans required for processing
        voltageScaleFactor    % Scale factor for voltage data conversion
        maxDataPoints         % Maximum number of data points to store
    end

    %% Internal Properties
    properties (SetAccess = {?DAQ_controller ?instrumentType}, GetAccess = public)
        % Properties managed internally by the class
        manufacturer           % DAQ device manufacturer
        analogPortNames        % Available analog port names
        digitalPortNames       % Available digital port names
        counterPortNames       % Available counter port names
        daqName               % Name of the connected DAQ device
        handshake             % DAQ device connection handle
        channelInfo           % Channel configuration information
        clockPort             % Clock port configuration
        dataChannels          % Available data channels
        errorLog              % Log of up to past 100 errors
        timeOfLastErrorReport % Logged time for when a warning was last given during data collection
        nErrors
    end

    %% Read-only Properties
    properties (SetAccess = {?DAQ_controller ?instrumentType}, GetAccess = public)
        % Properties that are read-only for users
        sampleRate            % Current sample rate
        toggleChannel         % Channel used for toggling data collection
        signalReferenceChannel % Channel used for signal/reference differentiation
        % dataPointsTaken       % Number of data points collected
        dataAcquirementMethod % Method used for data acquisition
        signal
        reference
        nPoints
        currentCounts
        selectedDataChannel
        dataType
    end

    % properties (Dependent, SetAccess = {?DAQ_controller ?instrumentType}, GetAccess = public)
    %     % Properties that are read-only for users
    %     sampleRate            % Current sample rate
    %     toggleChannel         % Channel used for toggling data collection
    %     signalReferenceChannel % Channel used for signal/reference differentiation
    %     dataPointsTaken       % Number of data points collected
    %     dataAcquirementMethod % Method used for data acquisition
    % end

    methods

        function obj = DAQ_controller(configFileName)
            %DAQ_controller Creates a new DAQ controller instance
            %
            %   obj = DAQ_controller(configFileName) creates a new DAQ controller
            %   using the specified configuration file.
            %
            %   Throws:
            %       error - If configFileName is not provided

            if nargin < 1
                error('DAQ_controller:MissingConfig', 'Config file name required as input')
            end

            %Loads config file and checks relevant field names
            configFields = {'channelInfo','clockPort','manufacturer','identifier','sampleRate',...
                'scanBufferMultiplier','minScansAvailable','maxErrorCount',...
                'voltageScaleFactor','maxDataPoints'};
            commandFields = {};
            numericalFields = {}; %has units, conversion factor, and min/max
            obj = loadConfig(obj,configFileName,configFields,commandFields,numericalFields);

        end

        function obj = connect(obj)
            %connect Establishes connection with the DAQ device
            %
            %   connect(obj) connects to the DAQ device and initializes
            %   channels and settings.
            %
            %   Throws:
            %       error - If DAQ is already connected or multiple DAQs detected

            if obj.connected
                error('DAQ_controller:AlreadyConnected', 'DAQ is already connected')
            end

            %Suppresses a warning generated by daq code provided by matlab
            warning('off','MATLAB:subscripting:noSubscriptsSpecified');

            %Checks if config channel labels are valid
            channels = squeeze(struct2cell(obj.channelInfo));
            channels = channels(strcmp(fieldnames(obj.channelInfo),'label'),:);

            obj.dataChannels = find(contains(lower(channels),'data'));
            obj.toggleChannel = find(contains(lower(channels),'toggle')  | contains(lower(channels),'enable'));
            obj.signalReferenceChannel = find(contains(lower(channels),'signal') | contains(lower(channels),'reference'));

            if isempty(obj.dataChannels)
                error('DAQ_controller:MissingDataChannel', 'Config file must contain a channel with a label containing "data"')
            end
            if numel(obj.toggleChannel) ~= 1
                error('DAQ_controller:InvalidToggleChannel', 'Config file must contain exactly 1 channel with a label containing "toggle" or "enable"')
            end
            if numel(obj.signalReferenceChannel) ~= 1
                error('DAQ_controller:InvalidSignalChannel', 'Config file must contain exactly 1 channel with a label containing "signal" or "reference"')
            end

            %Find non-simulated device
            devices = daqlist;
            isSimulated = [devices.DeviceInfo.IsSimulated];
            obj.daqName = devices.DeviceID(~isSimulated);

            if numel(obj.daqName) > 1
                error('DAQ_controller:MultipleDevices', 'Multiple DAQs detected')
            end

            %Store port names
            obj.analogPortNames = devices.DeviceInfo(~isSimulated).Subsystems(1).ChannelNames;
            obj.digitalPortNames = devices.DeviceInfo(~isSimulated).Subsystems(3).ChannelNames;
            obj.counterPortNames = devices.DeviceInfo(~isSimulated).Subsystems(4).ChannelNames;

            %Create DAQ connection
            obj.handshake = daq(obj.manufacturer);
            obj.handshake.Rate = obj.sampleRate;

            obj.connected = true;
            obj.identifier = 'DAQ';

            %Set default values
            setDataChannel(obj,1);
            obj.continuousCollection = true;
            obj.differentiateSignal = true;
            obj.takeData = false;
            obj.nPoints = 0;
            % obj.toggleChannels = obj.defaults.toggleChannel;
            % obj.signalReferenceChannels = obj.defaults.signalReferenceChannel;
            obj.errorLog = {};
            obj.timeOfLastErrorReport = datetime;

            %Creates a weak reference to prevent memory leak
            weakObj = matlab.lang.WeakReference(obj);

            %Set data collection callback
            obj.handshake.ScansAvailableFcn = @(src, evt) DAQ_controller.storeData(src, evt, weakObj);

            %Add channels
            for ii = 1:numel(obj.channelInfo)
                addChannel(obj,obj.channelInfo(ii));
            end

            %Sets variables based on presets by forced get request
            [~] = obj.maxErrorCount;
            [~] = obj.voltageScaleFactor;
            [~] = obj.scanBufferMultiplier;
            [~] = obj.minScansAvailable;
            [~] = obj.voltageScaleFactor;
            [~] = obj.maxDataPoints;
        end

        function obj = disconnect(obj)
            %disconnect Disconnects from the DAQ device
            %
            %   disconnect(obj) disconnects from the DAQ device and cleans up
            %   resources.

            if ~obj.connected
                return;
            end
            if ~isempty(obj.handshake)
                obj.handshake = [];
            end
            obj.connected = false;
        end

        function addChannel(obj,channelInfo)
            %addChannel Adds a channel to the DAQ device
            %
            %   addChannel(obj,channelInfo) adds a channel based on the
            %   provided configuration.
            %
            %   Required fields in channelInfo:
            %       - dataType: 'voltage', 'counter', or 'digital'
            %       - port: Port name for the channel
            %
            %   Throws:
            %       error - If required fields are missing or invalid

            mustContainField(channelInfo,{'dataType','port'})

            %Set data type and valid port names based on input type
            switch lower(channelInfo.dataType)
                case {'v','voltage','analog'}
                    dType = 'Voltage';
                    portNames = 'analogPortNames';
                case {'counter','cntr','count','edge','edge count','edgecount'}
                    dType = 'EdgeCount';
                    portNames = 'counterPortNames';
                case {'digital','binary'}
                    dType = 'Digital';
                    portNames = 'digitalPortNames';
                otherwise
                    error('DAQ_controller:InvalidDataType', ...
                        'Invalid dataType for channel %d. Must be "voltage", "counter", or "digital"',ii)
            end

            if ~any(strcmp(channelInfo.port,obj.(portNames)))
                error('DAQ_controller:InvalidPort', 'Invalid port name. See %s for valid names',portNames)
            end

            %Loads the indicated channel
            addinput(obj.handshake,obj.daqName,channelInfo.port,dType)
            obj.dataType = dType;
            % obj.handshake.UserData.dataType = dataType;
        end

        function setDataChannel(obj,channelDesignation)
            %setDataChannel Sets the active data channel
            %
            %   setDataChannel(obj,channelDesignation) sets the active data
            %   channel by number or name/port.
            %
            %   Throws:
            %       error - If channelDesignation is invalid

            %Number input
            if isa(channelDesignation,'double')
                if channelDesignation > numel(obj.channelInfo)
                    error('DAQ_controller:InvalidChannelNumber', ...
                        '%d is greater than the %d channels',channelDesignation,numel(obj.channelInfo))
                end
                obj.selectedDataChannel = channelDesignation;
                % obj.handshake.UserData.dataChannelNumber = channelDesignation;
                obj.activeDataChannel = obj.channelInfo(channelDesignation).label;
                return
            end

            %Label/port input
            channelNumber = getChannelIndex(obj, channelDesignation);
            obj.activeDataChannel = obj.channelInfo(channelNumber).label;
            obj.selectedDataChannel = channelNumber;
            % obj.handshake.UserData.dataChannelNumber = channelNumber;
            % dType = getDataType(obj, channelNumber);
            % obj.dataType = dType;
            % obj.handshake.UserData.dataType = dataType;
        end

        % function setSignalDifferentiation(obj,onOff)
        %     %setSignalDifferentiation Enables/disables signal/reference differentiation
        %     %
        %     %   Note: When enabled, continuous collection is automatically turned on
        % 
        %     obj.differentiateSignal = instrumentType.discernOnOff(onOff);
        %     if strcmp(obj.differentiateSignal,'on')
        %         obj.differentiateSignal = true;
        %         % obj.handshake.UserData.differentiateSignal = true;
        %         obj.continuousCollection = 'on';
        %     else
        %         obj.differentiateSignal = false;
        %         % obj.handshake.UserData.differentiateSignal = false;
        %     end
        % end

        % function setContinuousCollection(obj,onOff)
        %     %setContinuousCollection Sets continuous collection mode
        %     %
        %     %   obj = setContinuousCollection(obj,onOff) enables/disables
        %     %   continuous data collection.
        %     %
        %     %   Throws:
        %     %       error - If DAQ is not connected
        % 
        %     checkConnection(obj)
        %     obj.continuousCollection = instrumentType.discernOnOff(onOff);
        % end

        function resetDAQ(obj)
            %resetDAQ Resets DAQ counters and data collection
            %
            %   For continuous collection: resets accumulated data
            %   For discrete collection: prepares for new data collection

            if ~obj.connected
                error('DAQ not connected')
            end

            %If the DAQ is continuously gathering data (signal vs reference is
            %enabled AND/OR continuous is hard set)
            if obj.continuousCollection || obj.differentiateSignal
                % if strcmp(obj.continuousCollection,'on') || strcmp(instrumentType.discernOnOff(obj.handshake.UserData.differentiateSignal),'on')
                % %Set the reference and signal to 0
                % obj.handshake.UserData.reference = 0;
                % obj.handshake.UserData.signal = 0;
                % obj.handshake.UserData.nPoints = 0;
                % obj.handshake.UserData.currentCounts = 0;
                %Set the reference and signal to 0
                obj.reference = 0;
                obj.signal = 0;
                obj.nPoints = 0;
                obj.currentCounts = 0;
                %Turn on collection
                if ~obj.handshake.Running, start(obj.handshake,"continuous"), end
            else
                if obj.handshake.Running, stop(obj.handshake), end
                resetcounters(obj.handshake)
            end
        end

        function varargout = readDAQData(obj)
            %readDAQData Reads data from the DAQ
            %
            %   [ref, sig] = readDAQData(obj) returns reference and signal values.
            %   For continuous collection with differentiation, both values are
            %   returned. For continuous collection without differentiation, only
            %   reference is returned. For discrete collection, a single value
            %   is returned.

            if obj.differentiateSignal
                varargout{1} = obj.reference;
                varargout{2} = obj.signal;
                % varargout{1} = obj.handshake.UserData.reference;
                % varargout{2} = obj.handshake.UserData.signal;
            elseif obj.continuousCollection
                varargout{1} = obj.reference;
                % varargout{1} = obj.handshake.UserData.reference;
            else
                if obj.handshake.Running,   stop(obj.handshake), end
                unsortedData = read(obj.handshake,"OutputFormat","Matrix");
                varargout{1} = unsortedData(obj.selectedDataChannel);
                % varargout{1} = unsortedData(obj.handshake.UserData.dataChannelNumber);
            end
        end

    end

    methods
        % function obj = setParameter(obj,val,varName)
        %     if obj.connected
        %         obj.handshake.UserData.(varName) = val;
        %     else
        %         obj.presets.(varName) = val;
        %     end
        % end
        % function val = getParameter(obj,varName)
        %     if obj.connected
        %         if ~isfield(obj.handshake.UserData,varName) || isempty(obj.handshake.UserData.(varName))
        %             if isfield(obj.presets,varName) && ~isempty(obj.presets.(varName))
        %                 obj.handshake.UserData.(varName) = obj.presets.(varName);
        %             elseif isfield(obj.defaults,varName)
        %                 obj.handshake.UserData.(varName) = obj.defaults.(varName);
        %             end
        %         end
        %         val =  obj.handshake.UserData.(varName);
        %     elseif isfield(obj.presets,varName) && ~isempty(obj.presets.(varName))
        %         val = obj.presets.(varName);
        %     elseif isfield(obj.defaults,varName) && ~isempty(obj.defaults.(varName))
        %         val = obj.defaults.(varName);
        %     else
        %         val  =[];
        %     end
        % end

        % function set.continuousCollection(obj,val)
        %     obj = setParameter(obj,instrumentType.discernOnOff(val),'continuousCollection');
        %     if strcmpi(instrumentType.discernOnOff(val),'off')
        %         obj = setParameter(obj,'off','differentiateSignal');%#ok<NASGU>
        %     end
        % end
        % function val = get.continuousCollection(obj)
        %     val = getParameter(obj,'continuousCollection');
        % end

        % function set.takeData(obj,val)
        %     obj = setParameter(obj,val,'takeData'); %#ok<NASGU>
        % end
        % function val = get.takeData(obj)
        %     val = getParameter(obj,'takeData');
        % end

        % function set.differentiateSignal(obj,val)
        %     obj = setParameter(obj,instrumentType.discernOnOff(val),'differentiateSignal');
        %     if strcmpi(instrumentType.discernOnOff(val),'on')
        %         obj = setParameter(obj,'on','continuousCollection');%#ok<NASGU>
        %     end
        % end
        % function val = get.differentiateSignal(obj)
        %     val = getParameter(obj,'differentiateSignal');
        % end

        % function set.maxErrorCount(obj,val)
        %     obj = setParameter(obj,val,'maxErrorCount'); %#ok<NASGU>
        % end
        % function val = get.maxErrorCount(obj)
        %     val = getParameter(obj,'maxErrorCount');
        % end
        % 
        % function set.errorLog(obj,val)
        %     obj = setParameter(obj,val,'errorLog'); %#ok<NASGU>
        % end
        % function val = get.errorLog(obj)
        %     val = getParameter(obj,'errorLog');
        % end
        % 
        % function set.timeOfLastErrorReport(obj,val)
        %     obj = setParameter(obj,val,'timeOfLastErrorReport'); %#ok<NASGU>
        % end
        % function val = get.timeOfLastErrorReport(obj)
        %     val = getParameter(obj,'timeOfLastErrorReport');
        % end
        % 
        % function set.scanBufferMultiplier(obj,val)
        %     obj = setParameter(obj,val,'scanBufferMultiplier'); %#ok<NASGU>
        % end
        % function val = get.scanBufferMultiplier(obj)
        %     val = getParameter(obj,'scanBufferMultiplier');
        % end
        % 
        % function set.minScansAvailable(obj,val)
        %     obj = setParameter(obj,val,'minScansAvailable'); %#ok<NASGU>
        % end
        % function val = get.minScansAvailable(obj)
        %     val = getParameter(obj,'minScansAvailable');
        % end
        % 
        % function set.voltageScaleFactor(obj,val)
        %     obj = setParameter(obj,val,'voltageScaleFactor'); %#ok<NASGU>
        % end
        % function val = get.voltageScaleFactor(obj)
        %     val = getParameter(obj,'voltageScaleFactor');
        % end
        % 
        % function set.maxDataPoints(obj,val)
        %     obj = setParameter(obj,val,'voltageScaleFactor'); %#ok<NASGU>
        % end
        % function val = get.maxDataPoints(obj)
        %     val = getParameter(obj,'voltageScaleFactor');
        % end

        function set.activeDataChannel(obj,val)
            %Sets active data channel number/name based on designation given.
            %Designation can be the channel port or channel label so long as it is unique to that channel
            if ~obj.connected
                obj.presets.activeDataChannel = val;
                return
            end
            obj.activeDataChannel = getChannelIndex(obj, val);        
            %set data type based on active data channel
            obj.dataType = getDataType(obj, obj.activeDataChannel); %#ok<MCSUP>
        end
        % function val = get.activeDataChannel(obj)
        %     val = obj.channelInfo(getParameter(obj,'dataChannelNumber')).label;
        % end

        %Properties below are read-only
        % function set.toggleChannel(obj,val)
        %     if ~obj.connected
        %         obj.presets.toggleChannel = val;
        %         return
        %     end
        %     channelNumber = getChannelIndex(obj, val);
        %     obj.handshake.UserData.toggleChannel = channelNumber;
        % end
        % function val = get.toggleChannel(obj)
        %     val = getParameter(obj,'toggleChannel');
        % end
        % 
        % function set.signalReferenceChannel(obj,val)
        %     if ~obj.connected
        %         obj.presets.signalReferenceChannel = val;
        %         return
        %     end
        %     channelNumber = getChannelIndex(obj, val);
        %     obj.handshake.UserData.signalReferenceChannel = channelNumber;
        % end
        % function val = get.signalReferenceChannel(obj)
        %     val = getParameter(obj,'signalReferenceChannel');
        % end
        % 
        % function set.sampleRate(obj,val)
        %     if obj.connected
        %         obj.handshake.Rate = val;
        %     else
        %         obj.presets.sampleRate = val;
        %     end
        % end
        % function val = get.sampleRate(obj)
        %     varName = 'sampleRate';
        %     if obj.connected
        %         val =  obj.handshake.Rate;
        %     elseif isfield(obj.presets,varName) && ~isempty(obj.presets.(varName))
        %         val = obj.presets.(varName);
        %     elseif isfield(obj.defaults,varName) && ~isempty(obj.defaults.(varName))
        %         val = obj.defaults.(varName);
        %     else
        %         val  =[];
        %     end
        % end

        % function val = get.dataPointsTaken(obj)
        %     val = getParameter(obj,'nPoints');
        % end
        % 
        % function val = get.dataAcquirementMethod(obj)
        %     val = getParameter(obj,'dataType');
        % end

    end

    methods (Access = private)
        function idx = getChannelIndex(obj, designation)
            % Returns the index of the channel matching the designation (label or port)
            channels = squeeze(struct2cell(obj.channelInfo));
            labels = channels(strcmp(fieldnames(obj.channelInfo),'label'),:);
            ports = channels(strcmp(fieldnames(obj.channelInfo),'port'),:);
            idx = find(contains(lower(labels),lower(designation)) | contains(lower(ports),lower(designation)));
            if numel(idx) ~= 1
                error('%s is an invalid channel designation. A designation must correspond to exactly 1 channel''s port or label', designation);
            end
        end

        function dataType = getDataType(obj, channelNumber)
            % Returns the data type of the specified channel
            switch lower(obj.channelInfo(channelNumber).dataType)
                case {'v','voltage','analog'}
                    dataType = 'Voltage';
                case {'counter','cntr','count','edge','edge count','edgecount'}
                    dataType = 'EdgeCount';
                case {'digital','binary'}
                    dataType = 'Digital';
            end
        end
    end

    methods (Static)
        function storeData(handshake,~,weakRef)
            %storeData Callback function for processing DAQ data
            %
            %   Processes data when available and updates accumulated values.
            %   Handles both counter and voltage data types.

            % if ~weakRef.isvalid
            %     return; % Wrapper was deleted; abort processing
            % end
            weakObj = weakRef.Handle();
            if isempty(weakObj) || ~isvalid(weakObj)
                return;
            end
            weakObj.nErrors = 0;

            while weakObj.nErrors < weakObj.maxErrorCount
                try

                    isValid = weakObj.takeData && ...
                ~isempty(weakObj.activeDataChannel) && ...
                ~isempty(weakObj.toggleChannel) && ...
                (~isempty(weakObj.signalReferenceChannel) || ...
                ~weakObj.differentiateSignal);
                    % Get collection info and validate data collection state
                    if ~isValid
                        return;
                    end

                    % Read data from DAQ
                    [unsortedData, ~] = DAQ_controller.readHandshake(handshake);
                    if isempty(unsortedData)
                        if weakObj.nErrors > 0 && seconds(datetime-weakObj.timeOfLastErrorReport) > 3
                            warning('DAQ_controller:ErrorInCollection', ...
                                ['Error occurred in data collection, followup read attempts resulted in no data available in DAQ buffer\n'...
                                'Check DAQ_controller error log for details, likely under ex.DAQ.errorLog'])
                            weakObj.timeOfLastErrorReport = datetime;
                        end
                        return;
                    end

                    % Process data based on type
                    if strcmpi(weakObj.dataType, 'EdgeCount')
                        [sig, ref] = DAQ_controller.processCounterData(weakObj,unsortedData);
                    else
                        [sig, ref] = DAQ_controller.processVoltageData(weakObj,unsortedData);
                    end

                    % Update handshake data
                    weakObj.reference = weakObj.reference + ref;
                    weakObj.signal = weakObj.signal + sig;

                    if ref ~= 0
                        weakObj.nPoints = weakObj.nPoints + ...
                            sum(logical(unsortedData(:, weakObj.toggleChannel)));                        
                    end
                    

                catch ME
                    %Log number of errors as well as adding to the overall error log
                    weakObj.nErrors = weakObj.nErrors + 1;
                    if numel(weakObj.errorLog) >= 100
                        weakObj.errorLog(1) = [];
                    end
                    weakObj.errorLog{end+1} = ME;
                end
            end
            if weakObj.nErrors >= weakObj.maxErrorCount && seconds(datetime-weakObj.timeOfLastErrorReport) > 3
                warning('DAQ_controller:MaxErrorsExceeded', ...
                    'Maximum number of errors (%d) exceeded. Stopping data collection.', ...
                    weakObj.maxErrorCount);
                weakObj.timeOfLastErrorReport = datetime;
            end
        end

        % function storeData(handshake,~,weakObj)
        %     %storeData Callback function for processing DAQ data
        %     %
        %     %   Processes data when available and updates accumulated values.
        %     %   Handles both counter and voltage data types.
        % 
        %     handshake.UserData.numErrors = 0;
        % 
        %     while handshake.UserData.numErrors < handshake.UserData.maxErrorCount
        %         try
        %             % Get collection info and validate data collection state
        %             collectionInfo = handshake.UserData;
        %             if ~DAQ_controller.isValidCollectionState(collectionInfo)
        %                 return;
        %             end
        % 
        %             % Read data from DAQ
        %             [unsortedData, ~] = DAQ_controller.readHandshake(handshake);
        %             if isempty(unsortedData)
        %                 if handshake.UserData.numErrors > 0 && seconds(datetime-handshake.UserData.timeOfLastErrorReport) > 3
        %                     warning('DAQ_controller:ErrorInCollection', ...
        %                         ['Error occurred in data collection, followup read attempts resulted in no data available in DAQ buffer\n'...
        %                         'Check DAQ_controller error log for details, likely under ex.DAQ.errorLog'])
        %                     handshake.UserData.timeOfLastErrorReport = datetime;
        %                 end
        %                 return;
        %             end
        % 
        %             % Process data based on type
        %             if strcmpi(collectionInfo.dataType, 'EdgeCount')
        %                 [sig, ref] = DAQ_controller.processCounterData(unsortedData, collectionInfo);
        %             else
        %                 [sig, ref] = DAQ_controller.processVoltageData(unsortedData, collectionInfo);
        %             end
        % 
        %             % Update handshake data
        %             DAQ_controller.updateHandshakeData(handshake, sig, ref, collectionInfo, unsortedData);
        % 
        %         catch ME
        %             %Log number of errors as well as adding to the overall error log
        %             handshake.UserData.numErrors = handshake.UserData.numErrors + 1;
        %             if numel(handshake.UserData.errorLog) >= 100
        %                 handshake.UserData.errorLog(1) = [];
        %             end
        %             handshake.UserData.errorLog{end+1} = ME;
        %         end
        %     end
        %     if handshake.UserData.numErrors >= handshake.UserData.maxErrorCount && seconds(datetime-handshake.UserData.timeOfLastErrorReport) > 3
        %         warning('DAQ_controller:MaxErrorsExceeded', ...
        %             'Maximum number of errors (%d) exceeded. Stopping data collection.', ...
        %             handshake.UserData.maxErrorCount);
        %         handshake.UserData.timeOfLastErrorReport = datetime;
        %     end
        % end

        function isValid = isValidCollectionState(collectionInfo)
            %isValidCollectionState Validates data collection state
            %
            %   Returns true if all required channels are configured and
            %   data collection is enabled.

            isValid = collectionInfo.takeData && ...
                ~isempty(collectionInfo.activeDataChannel) && ...
                ~isempty(collectionInfo.toggleChannel) && ...
                (~isempty(collectionInfo.signalReferenceChannel) || ...
                ~collectionInfo.differentiateSignal);
        end

        function [unsortedData, scansAvailable] = readHandshake(handshake)
            %readHandshake Reads available data from DAQ
            %
            %   Returns raw data matrix and number of available scans.
            %   Handles buffer overflow conditions.

            scansAvailable = handshake.NumScansAvailable - 25;

            if ~isfield(handshake.UserData,'ndiscards')
                handshake.UserData.ndiscards = 0;
            end

            % Handle buffer overflow
            if scansAvailable > handshake.ScansAvailableFcnCount * 20
                multDiscard = 19;
                [~] = read(handshake, handshake.ScansAvailableFcnCount*multDiscard, "OutputFormat", "Matrix");
                handshake.UserData.ndiscards = handshake.UserData.ndiscards+1;
                fprintf('Discarded %d scans\n Number of total discards: %d\n',handshake.ScansAvailableFcnCount*multDiscard,handshake.UserData.ndiscards)
                unsortedData = [];
                return;
            end

            if scansAvailable <= 0
                unsortedData = [];
                return;
            end

            unsortedData = read(handshake, scansAvailable, "OutputFormat", "Matrix");
        end

        function [sig, ref] = processCounterData(weakObj,unsortedData)
            %processCounterData Processes counter data
            %
            %   Handles signal/reference differentiation for counter data.
            %   Validates counts and discards negative values.

            counterDifference = diff(unsortedData(:, weakObj.activeDataChannel));
            dataOn = unsortedData(2:end, weakObj.toggleChannel);

            if ~collectionInfo.differentiateSignal
                sig = 0;
                ref = sum(counterDifference(dataOn));
            else
                signalOn = unsortedData(2:end, weakObj.signalReferenceChannel);
                sig = sum(counterDifference(signalOn & dataOn));
                ref = sum(counterDifference(~signalOn & dataOn));
            end

            % Validate counts
            if ref < 0 || sig < 0
                warning('DAQ_controller:NegativeCounts', 'Negative counts obtained, discarding data');
                sig = 0;
                ref = 0;
            end
            weakObj.currentCounts = unsortedData(end,weakObj.activeDataChannel);
        end

        % function [sig, ref] = processCounterData(unsortedData, collectionInfo)
        %     %processCounterData Processes counter data
        %     %
        %     %   Handles signal/reference differentiation for counter data.
        %     %   Validates counts and discards negative values.
        % 
        %     counterDifference = diff(unsortedData(:, collectionInfo.dataChannelNumber));
        %     dataOn = unsortedData(2:end, collectionInfo.toggleChannel);
        % 
        %     if ~collectionInfo.differentiateSignal
        %         sig = 0;
        %         ref = sum(counterDifference(dataOn));
        %     else
        %         signalOn = unsortedData(2:end, collectionInfo.signalReferenceChannel);
        %         sig = sum(counterDifference(signalOn & dataOn));
        %         ref = sum(counterDifference(~signalOn & dataOn));
        %     end
        % 
        %     % Validate counts
        %     if ref < 0 || sig < 0
        %         warning('DAQ_controller:NegativeCounts', 'Negative counts obtained, discarding data');
        %         sig = 0;
        %         ref = 0;
        %     end
        % end

        function [sig, ref, newPoints] = processVoltageData(obj, unsortedData)
            %processVoltageData Processes voltage data
            %
            %   Handles signal/reference differentiation for voltage data.
            %   Returns zero values if no data is available.

            dataOn = logical(unsortedData(:, obj.toggleChannel));

            % if ~any(dataOn)
            %     sig = 0;
            %     ref = 0;
            %     return;
            % end

            % newPoints = sum(logical(unsortedData(:, obj.toggleChannel)));
            newPoints = nnz(dataOn);

            if newPoints == 0
                sig = 0;
                ref = 0;
                return;
            end
                

            if ~obj.differentiateSignal
                ref = sum(unsortedData(dataOn, obj.activeDataChannel));
                sig = 0;
            else
                % signalOn = logical(unsortedData(:, obj.signalReferenceChannel));
                % sig = sum(unsortedData(dataOn & signalOn, obj.activeDataChannel));
                % ref = sum(unsortedData(dataOn & ~signalOn, obj.activeDataChannel));
                signalOn = unsortedData(:, obj.signalReferenceChannel) ~= 0;
                idxSig = dataOn & signalOn;
                idxRef = dataOn & ~signalOn;
                sig = sum(unsortedData(idxSig, obj.activeDataChannel));
                ref = sum(unsortedData(idxRef, obj.activeDataChannel));
            end
        end

        % function [sig, ref] = processVoltageData(unsortedData, collectionInfo)
        %     %processVoltageData Processes voltage data
        %     %
        %     %   Handles signal/reference differentiation for voltage data.
        %     %   Returns zero values if no data is available.
        % 
        %     dataOn = logical(unsortedData(:, collectionInfo.toggleChannel));
        % 
        %     if ~any(dataOn)
        %         sig = 0;
        %         ref = 0;
        %         return;
        %     end
        % 
        %     if ~collectionInfo.differentiateSignal
        %         ref = sum(unsortedData(dataOn, collectionInfo.dataChannelNumber));
        %         sig = 0;
        %     else
        %         signalOn = logical(unsortedData(:, collectionInfo.signalReferenceChannel));
        %         sig = sum(unsortedData(dataOn & signalOn, collectionInfo.dataChannelNumber));
        %         ref = sum(unsortedData(dataOn & ~signalOn, collectionInfo.dataChannelNumber));
        %     end
        % end

        function updateHandshakeData(handshake, sig, ref, collectionInfo, unsortedData)
            %updateHandshakeData Updates accumulated values
            %
            %   Updates signal, reference, and point count in handshake data.

            handshake.UserData.reference = handshake.UserData.reference + ref;
            handshake.UserData.signal = handshake.UserData.signal + sig;

            if ref ~= 0
                handshake.UserData.nPoints = handshake.UserData.nPoints + ...
                    sum(logical(unsortedData(:, collectionInfo.toggleChannel)));
            elseif ~isfield(handshake.UserData, 'nPoints')
                handshake.UserData.nPoints = 0;
            end
        end

    end
end



