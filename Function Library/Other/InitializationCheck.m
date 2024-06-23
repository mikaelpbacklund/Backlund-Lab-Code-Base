function InitializationCheck(instrumentName)
%Checks to see if instrument is initialized and if not, initializes it

%InitializationCheck v1.0 4/19/22

global master

%Checks if notifications settings are present and if not, sets
%notifications to on
%By being in this script, most other scripts do not need this
if ~isfield(master,'notifications'),      master.notifications = true;     end

isinitialized = false;

switch instrumentName
   
   case 'stage'
      if isfield(master,'stage')
         if isfield(master.stage,'initialized')
            if master.stage.initialized
               isinitialized =true;
            end
         end
      end
      if ~isinitialized
         if master.notifications
            fprintf('Stage not initialized. Beginning intialization\n');
         end
         StageInitialization
      end
      
   case 'NDYOV'
      if isfield(master,'NDYOV')
         if isfield(master.NDYOV,'initialized')
            if master.NDYOV.initialized
               isinitialized =true;
            end
         end
      end
      if ~isinitialized
         if master.notifications
            fprintf('Nd:YOV laser not initialized. Beginning intialization\n');
         end
         NDYOVInitialization
      end
      
      case 'sCMOS'
      if isfield(master,'sCMOS')
         if isfield(master.sCMOS,'initialized')
            if master.sCMOS.initialized
               isinitialized =true;
            end
         end
      end
      if ~isinitialized
         if master.notifications
            fprintf('sCMOS not initialized. Beginning intialization\n');
         end
         sCMOSInitialization
      end
      
      case 'RF'
      if isfield(master,'RF')
         if isfield(master.RF,'initialized')
            if master.RF.initialized
               isinitialized =true;
            end
         end
      end
      if ~isinitialized
         if master.notifications
            fprintf('RF generator not initialized. Beginning intialization\n');
         end
         RFInitialization
      end
      
      case 'PB'
      if isfield(master,'PB')
         if isfield(master.PB,'initialized')
            if master.PB.initialized
               isinitialized =true;
            end
         end
      end
      if ~isinitialized
         if master.notifications
            fprintf('Pulse blaser not initialized. Beginning intialization\n');
         end
         PBInitialization
      end
      
      case 'NIDAQ'
      if isfield(master,'NIDAQ')
         if isfield(master.NIDAQ,'initialized')
            if master.NIDAQ.initialized
               isinitialized =true;
            end
         end
      end
      if ~isinitialized
         if master.notifications
            fprintf('NI DAQ not initialized. Beginning intialization\n');
         end
         NIDAQInitialization
      end
      
   otherwise
      error('Invalid instrument name for first input in InitializationCheck function')
      
end



end

