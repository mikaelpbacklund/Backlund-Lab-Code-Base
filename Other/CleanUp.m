function CleanUp(instrumentToClean)
%Disconnects instrument specified in first argument. If argument is "all",
%disconnects all connected instruments instead

%CleanUp v1.1 4/20/22

global master %#ok<*GVMIS> 

if ~isfield(master,'notifications'),      master.notifications = true;     end

if nargin == 0
   cleanonly = "all";
else
   cleanonly = instrumentToClean;
end

try
   
   %Cleans stage if stage or all is selected and the stage is already
   %initialized. this is repeated for each instrument
    if master.stage.initialized && (strcmp(cleanonly,"stage") || strcmp(cleanonly,"all"))
       
        global coarseXYControl %#ok<*TLEV,*NUSED>
        global coarseZControl
        global fineControl
        global PIController
        
        coarseXYControl.CloseConnection;
        coarseZControl.CloseConnection;
        fineControl.CloseConnection;
        PIController.Destroy;
        clear global PIController
        clear global coarseXYControl;
        clear global coarseZControl;
        clear global fineControl;
        master.stage.initialized = false;
        
        if master.notifications
        fprintf('PI stages successfully disconnected\n')
        end
        
    end
catch ME
    master.test.failedcleanup = ME;
end

try
    if master.sCMOS.initialized && (strcmp(cleanonly,"sCMOS") || strcmp(cleanonly,"all"))
        
        global hamm
        global hammsource
        
        delete hamm
        delete hammsource
        clear global hamm
        clear global hammsource
        master.sCMOS.initialized = false;

        if master.notifications
        fprintf('sCMOS camera successfully disconnected\n')   
        end
    end
catch
end

try
    if master.PB.initialized && (strcmp(cleanonly,"PB") || strcmp(cleanonly,"all"))
        
        [~] = calllib(master.PB.dllname,'pb_close');
        unloadlibrary(master.PB.dllname)
        master.PB.initialized = false;
        
        if master.notifications
        fprintf('Pulse blaster successfully disconnected\n')
        end
    end
catch
end
      
try
    if master.RF.initialized && (strcmp(cleanonly,"RF") || strcmp(cleanonly,"all"))
        
        global RF
        fclose(RF);
        delete(RF)
        clear global RF
        master.RF.initialized = false;
        
         if master.notifications
        fprintf('SRS RF generator successfully disconnected\n')
         end
        
    end
catch
end

try
    if master.NIDAQ.initialized && (strcmp(cleanonly,"NIDAQ") || strcmp(cleanonly,"all"))
        
        global NIDAQ
        clear NIDAQ
        clear global NIDAQ
        master.NIDAQ.initialized = 0;
        
        if master.notifications
        fprintf('NI DAQ successfully disconnected\n')
        end
        
    end
catch
end

try
    if master.NDYOV.initialized && (strcmp(cleanonly,"NDYOV") || strcmp(cleanonly,"all"))
        
        global NDYOV
        if master.NDYOV.switch == "on" && master.NDYOV.offwhencleaned
            master.NDYOV.switch = "off";
            NDYOVSwitch
        end
        clear global NDYOV
        master.NDYOV.initialized = 0;
        
        if master.notifications
        fprintf('Nd:YOV laser successfully disconnected\n')
        end
        
    end
catch
end


end