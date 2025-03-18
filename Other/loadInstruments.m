function ex = loadInstruments(ex,instrumentNames,instrumentConfigs,varargin)
%Loads instruments given by instrumentNames using configs given by instrumentConfigs

if isempty(ex)
   ex = experiment;
end

if nargin >= 4
   giveAlreadyPresentWarning = varargin{1};
else
   giveAlreadyPresentWarning = true;
end

instrumentNames = string(instrumentNames);
instrumentConfigs = string(instrumentConfigs); %#ok<NASGU>

for ii = 1:numel(instrumentNames)
   switch lower(instrumentNames(ii))
      
      case {'pb','pulse blaster','pulseblaster','pulse_blaster'}
         ex = connectToInstrument(ex,'pulse blaster','pulse_blaster');

      case {'srs','srsrf','srs_rf','srs rf','rf','rf generator','rfgenerator','rf_generator'}
         ex = connectToInstrument(ex,'SRS RF','RF_generator');

      case {'wf','windfreak','windfreakrf','windfreak_rf','windfreak rf'}
         ex = connectToInstrument(ex,'windfreak RF','RF_generator');

      case {'stage','pistage','pi_stage','pi stage'}
         ex = connectToInstrument(ex,'stage','stage','PIstage');

      case {'daq','nidaq','ni daq','ni_daq','data','data acquisition'}
         ex = connectToInstrument(ex,'DAQ','DAQ_controller');

      case {'ndyag','ndyov','532','532 nm','532nm','green laser','nv laser'}
         ex = connectToInstrument(ex,'ndYAG','laser');
   end
end


   function ex = connectToInstrument(ex,experimentPropertyName,className,varargin)
      informalName = experimentPropertyName;
      if nargin >= 4
         if ~strcmp(varargin{1},experimentPropertyName)
            informalName = varargin{1};
         end
      end
      if isempty(ex.(experimentPropertyName)) || ex.(experimentPropertyName).connected == 0
         fprintf('Connecting to %s...\n',informalName)
         ex.(experimentPropertyName) = eval(sprintf('%s(instrumentConfigs(ii))',className));
         ex.(experimentPropertyName) = connect(ex.(experimentPropertyName));
         fprintf('%s connected\n',informalName)
      elseif giveAlreadyPresentWarning
         warning('%s already present',informalName)
      end
   end

end
