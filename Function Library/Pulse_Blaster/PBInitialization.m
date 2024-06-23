function PBInitialization
%Initializes Pulse Blaster for use later

%Instrument dependencies: none

%Code dependencies: 
%Matlab_SpinAPI folder

%PBInitialization v2.0 5/26/22


global master %#ok<*GVMIS> 

if ~isfield(master,'notifications')
    master.notifications = true;
end

%Checks if masterSettings.sCMOS.initialized exists in usable form. If not,
%makes said variable = 0
% Commented by Swastik - To make a short workaround for Rabi code
iscorrect = false;
if isfield(master,'PB')
    if isfield(master.PB,'initialized')
        if isscalar(master.PB.initialized) && ~isstring(master.PB.initialized)
            iscorrect =true;
        end
    end
end
if ~iscorrect 
    master.PB.initialized = false;
end

%Begins initialization if not already initialized
if ~master.PB.initialized 

    try
    master.PB.dllpath = 'C:\SpinCore\SpinAPI\lib\';
    master.PB.dllname = 'spinapi64';
    
    warning('off','MATLAB:loadlibrary:FunctionNotFound') %Produces warning for pb_get_rounded_value not being in library
    loadlibrary(strcat(master.PB.dllpath, master.PB.dllname, '.dll'), 'C:\SpinCore\SpinAPI\include\spinapi.h', 'addheader','C:\SpinCore\SpinAPI\include\pulseblaster.h');
    warning('on','MATLAB:loadlibrary:FunctionNotFound')
    
    [~] = calllib(master.PB.dllname,'pb_init');
    calllib(master.PB.dllname,'pb_core_clock',500)

    if ~isfield(master.PB,'useInterpreter')
        master.PB.useInterpreter = true;
    end
    
    if ~isfield(master.PB,'addTotalLoops')
        master.PB.addTotalLoops = true;
    end
    
    if ~isfield(master.PB,'totalLoops')
        master.PB.totalLoops = 1;
    end
    
    if ~isfield(master.PB,'nchannels')
       master.PB.nchannels = 9;
    end
    
    if master.notifications
    fprintf("Pulse blaster initialized\n")
    end
    master.PB.initialized = 1;
    
    catch ME
        if master.notifications
        fprintf('Pulse blaster initialization failed. Have you downloaded the SpinCore API in the right location?\n')
        end
        rethrow(ME)
    end
    
else %If already initialized
    if master.notifications
    fprintf("Pulse blaster already initialized\n")
    end
end

end


