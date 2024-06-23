function [] = sCMOSInitialization()
%Initializes sCMOS camera for use later

%Instrument dependencies:
%Hamamatsu sCMOS camera

%Code dependencies: none

%Inputs:
%master.sCMOS.framesper : number of frames to take per image
%master.sCMOS.defect : in-built correction
%master.sCMOS.hotPixel : what level of correction should be used.
    %Only relevant if master.sCMOS.defect == "on"

global hamm %#ok<*GVMIS> 
global master
global hammsource

if ~isfield(master,'notifications')
    master.notifactions =true;
end

%Checks if masterSettings.sCMOS.initialized exists in usable form. If not,
%makes said variable = 0
iscorrect = false;
if isfield(master,'sCMOS')
    if isfield(master.sCMOS,'initialized')
        if isscalar(master.sCMOS.initialized) && ~isstring(master.sCMOS.initialized)
            iscorrect =true;
        end
    end
end
if ~iscorrect
    master.sCMOS.initialized = false;
end

%Begins initialization if not already initialized
if ~master.sCMOS.initialized 

    if master.notifications
        fprintf('Beginning sCMOS initialization\n')
    end

    %Attempts to connect hamamatsu with hamm vid object
    try
        hamm = videoinput('hamamatsu',1,'MONO16_2304x2304_SlowMode');
    catch
        error('Error connecting to sCMOS camera')
    end

    %Sets source variable for hamm vid object
    hammsource = getselectedsource(hamm);

    %If hotPixel settings not already present, requests user input 
    iscorrect = false;
    while ~iscorrect 
        if isfield(master.sCMOS,'defect')
            aa = master.sCMOS.defect;
            if isstring(aa)
                if aa == "on" || aa == "off" 
                    iscorrect = true;
                else
                    master.notifications
                    fprintf('Defect correction must be "on" or "off"\n')
                end
            else
               master.notifications
               fprintf("Defect correction must be a string\n")
            end
        end
        if ~iscorrect
            master.sCMOS.defect = input('Defect Correction "on" or "off"\n');
        end
    end
    
    if master.sCMOS.defect == "on"%Only applies hot pixel correction if defect correction is on
        %If hotPixel settings not already present, requests user input
        iscorrect = false;
        while ~iscorrect
            if isfield(master.sCMOS,'hotPixel')
                aa = master.sCMOS.hotPixel;
                if isstring(aa)
                    if aa == "minimum" || aa == "standard" || aa == "aggressive" || aa == "all"
                        iscorrect = true;
                    else
                        if master.notifications
                        fprintf("Hot pixel correction level must be one of proffered values\n")
                        end
                    end
                else
                    if master.notifications
                    fprintf("Hot pixel correction level must be a string\n")
                    end
                end
            end
            if ~iscorrect
                master.sCMOS.hotPixel = input('Hot pixel correction level? "minimum" "standard" "aggressive"\n');
            end
        end
        if master.sCMOS.hotPixel ~= "all"
            hammsource.HotPixelCorrectionLevel = master.sCMOS.hotPixel;
        else
            hammsource.HotPixelCorrectionLevel = "minimum";
        end        
    end

    %If framesper settings not already present, requests user input 
    iscorrect = false;
    while ~iscorrect 
        if isfield(master.sCMOS,'framesper')
            aa = master.sCMOS.framesper;
            if isscalar(aa) && ~isstring(aa)
                if 0 < aa && aa < 10001
                    iscorrect = true;
                else
                    fprintf("Frames per trigger must be between 1 and 10000")
                end
            else
                fprintf("Frames per trigger must be a scalar\n")
            end
        end
        if ~iscorrect 
            master.sCMOS.framesper = input('Frames per trigger?\n');
        end
    end

    
    hammsource.DefectCorrect = master.sCMOS.defect;
    
    hammsource.ExposureTime = 0.011240632352941;%Acceptable exposure time for software
    hamm.FramesPerTrigger = master.sCMOS.framesper;
    hamm.LoggingMode = 'memory';

    triggerconfig(hamm, 'immediate');%Triggers immediately after starting    

    master.sCMOS.initialized = true;%Changes initialization status to true
    
    if ~isfield(master.sCMOS,'xbounds')
        master.sCMOS.xbounds = [1 2304];       
    end
    if ~isfield(master.sCMOS,'ybounds')
        master.sCMOS.ybounds = [1 2304];       
    end
    master.sCMOS.iw = 1 + master.sCMOS.xbounds(2) - master.sCMOS.xbounds(1);
    master.sCMOS.ih = 1 + master.sCMOS.ybounds(2) - master.sCMOS.ybounds(1);    
    if ~isfield(master.sCMOS,'groupsets')
        master.sCMOS.groupsets = 0;%All sets in first group
    end    
    if ~isfield(master.sCMOS,'plots')
        master.sCMOS.plots.dark = false;
        master.sCMOS.plots.gain = false;
        master.sCMOS.plots.norm = false;
        master.sCMOS.plots.pixels.n = false;
        master.sCMOS.plots.save = false;
        master.sCMOS.plots.mean = false;
        master.sCMOS.plots.variance = false;
    else
        if ~isfield(master.sCMOS.plots,'mean')
            master.sCMOS.plots.mean = false;
        end
        if ~isfield(master.sCMOS.plots,'dark')
            master.sCMOS.plots.dark = false;
        end
        if ~isfield(master.sCMOS.plots,'variance')
            master.sCMOS.plots.variance = false;
        end
        if ~isfield(master.sCMOS.plots,'gain')
            master.sCMOS.plots.gain = false;
        end
        if ~isfield(master.sCMOS.plots,'norm')
            master.sCMOS.plots.norm = false;
        end
        if ~isfield(master.sCMOS.plots,'save')
            master.sCMOS.plots.save = false;
        end
        if ~isfield(master.sCMOS.plots,'pixels')
            master.sCMOS.plots.pixels.n = false;
        else
            if ~isfield(master.sCMOS.plots.pixels,'n')
                master.sCMOS.plots.pixels.n = 0;
                if ~isfield(master.sCMOS.plots.pixels,'rows')
                    master.sCMOS.plots.pixels.rows = 0;
                end
                if ~isfield(master.sCMOS.plots.pixels,'columns')
                    master.sCMOS.plots.pixels.columns = 0;
                end
                if ~isfield(master.sCMOS.plots.pixels,'locations')
                    master.sCMOS.plots.pixels.locations = [0 0];
                end
            else
                if ~isfield(master.sCMOS.plots.pixels,'rows')
                    master.sCMOS.plots.pixels.rows = zeros(1,master.sCMOS.plots.pixels.n);
                end
                if ~isfield(master.sCMOS.plots.pixels,'columns')
                    master.sCMOS.plots.pixels.columns = zeros(1,master.sCMOS.plots.pixels.n);
                end
                if ~isfield(master.sCMOS.plots.pixels,'locations')
                    master.sCMOS.plots.pixels.locations = [0 0];
                end
            end            
        end
    end
    if ~isfield(master.sCMOS,'imnum')
        master.sCMOS.imnum = false;
    end
    if ~isfield(master.sCMOS,'saveimage')
        master.sCMOS.saveimage = false;
    end
    if ~isfield(master.sCMOS,'sendping')
        master.sCMOS.sendping = false;
    end
    if ~isfield(master.sCMOS,'warningtime')
        master.sCMOS.warningtime = false;
    end

    master.sCMOS.initialized = true;

    if master.notifications
    fprintf("sCMOS initialized\n")
    end
    
else %If already initialized
    if master.notifications
    fprintf("sCMOS already initialized\n")
    end
end

end


