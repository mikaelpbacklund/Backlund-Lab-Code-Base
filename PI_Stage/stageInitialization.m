function stageInitialization
%Initializes PI stages for use later

%Instrument dependencies:
%Coarse XY, coarse Z, and fine XYZ controllers from PI

%Code dependencies: none

%stageInitialization v2.0 4/19/22

global master %#ok<*GVMIS>
global coarseXYControl
global coarseZControl
global fineControl
global PIController

if ~isfield(master,'notification'),    master.notifications = true;     end

%Checks if master.stage.initialized exists in usable form. If not,
%makes said variable false
iscorrect = false;
if isfield(master,'stage')
    if isfield(master.stage,'initialized')
        if isscalar(master.stage.initialized) && ~isstring(master.stage.initialized)
            iscorrect =true;
        end
    end
end
if ~iscorrect
    master.stage.initialized = false;
end

while true
    if isfield(master,'comp')
        aa = master.comp;
        if isstring(aa) || ischar(aa)
            if strcmp(aa,"NV") || strcmp(aa,"NV2") || strcmp(aa,"SMM")
                break
            else
                if master.notifications
                    fprintf('Computer designation must be either "NV", "NV2", or "SMM"\n')
                end
            end
        else
            if master.notifications
                fprintf("Computer designation must be a string\n")
            end
        end
    end
    master.comp = input('Computer designation? "NV", "NV2", or "SMM"\n');
end

if master.comp == "NV"
    cxy = '0121049372';
    cz = '0021550174';
    fcont = '0121029226';
elseif master.comp == "SMM"
    cxy = '0120040780';
    cz = '0020550159';
    fcont = '0120052260';
elseif master.comp == "NV2"
    cxy = '0122072241';
    cz = '0022550277';
    fcont = '0121044206';
end

if ~isfield(master.stage,'ignoreWait')
    master.stage.ignoreWait = false;
end

if ~isfield(master.stage,'doReset')
    master.stage.doReset = true;
end

%Begins initialization if not already initialized
if ~master.stage.initialized
    if master.notifications
        fprintf('Initializing PI stage...\n')
    end
    try
        %Connection to computer and loading drivers
        addpath (getenv ('PI_MATLAB_DRIVER'));
        PIController = PI_GCS_Controller();
    catch
        PIController.Destroy;
        clear PIController;
        error('Error connecting to computer. Good luck')
    end

    master.stage.axes = '121123';%Axes designation

    %Connection to stage controller
    try
        coarseXYControl = PIController.ConnectUSB (cxy);%Creates XY controller object
        coarseXYControl = coarseXYControl.InitializeController ();%Initializes XY controller
        coarseXYControl.SVO (master.stage.axes(1),1); %Servo 1 turned on for XY controller
        coarseXYControl.SVO (master.stage.axes(2),1);%Servo 2 turned on for XY controller
    catch
        PIController.Destroy;
        clear PIController;
        clear coarseXYControl;
        error('Error connecting to coarse xy controller')
    end

    %Repeat above for coarse z
    try
        coarseZControl = PIController.ConnectUSB (cz);
        coarseZControl = coarseZControl.InitializeController ();
        coarseZControl.SVO (master.stage.axes(3),1);
    catch
        PIController.Destroy;
        clear PIController;
        clear coarseZControl;
        clear coarseXYControl;
        error('Error connecting to coarse z controller')
    end

    %Repeat above for fine
    try
        fineControl = PIController.ConnectUSB (fcont);
        fineControl = fineControl.InitializeController ();
        fineControl.SVO (master.stage.axes(4),1);
        fineControl.SVO (master.stage.axes(5),1);
        fineControl.SVO (master.stage.axes(6),1);
    catch
        PIController.Destroy;
        clear PIController;
        clear fineControl;
        clear coarseZControl;
        clear coarseXYControl;
        error('Error connecting to fine controller')
    end

    %Finds minimum in micrometers
    master.stage.minBase(1) = coarseXYControl.qTMN (master.stage.axes(1))*1000;
    master.stage.minBase(2) = coarseXYControl.qTMN (master.stage.axes(2))*1000;
    master.stage.minBase(3) = coarseZControl.qTMN (master.stage.axes(3))*1000;
    master.stage.minBase(4) = fineControl.qTMN (master.stage.axes(4));
    master.stage.minBase(5) = fineControl.qTMN (master.stage.axes(5));
    master.stage.minBase(6) = fineControl.qTMN (master.stage.axes(6));

    %Finds maximum in micrometers
    master.stage.maxBase(1) = coarseXYControl.qTMX (master.stage.axes(1))*1000;
    master.stage.maxBase(2) = coarseXYControl.qTMX (master.stage.axes(2))*1000;
    master.stage.maxBase(3) = coarseZControl.qTMX (master.stage.axes(3))*1000;
    master.stage.maxBase(4) = fineControl.qTMX (master.stage.axes(1));
    master.stage.maxBase(5) = fineControl.qTMX (master.stage.axes(2));
    master.stage.maxBase(6) = fineControl.qTMX (master.stage.axes(3));

    %Finds total range of movement in micrometers
    master.stage.rangeBase = master.stage.maxBase - master.stage.minBase;

    %Adds 2% buffer region to prevent overflow
    master.stage.min = master.stage.minBase + master.stage.rangeBase*.03;
    master.stage.max = master.stage.maxBase - master.stage.rangeBase*.03;

    %Finds midpoint of each range
    master.stage.mid = master.stage.minBase + master.stage.rangeBase/2;

    %Queries current location in micrometers
    master.stage.loc(1) = -coarseXYControl.qPOS (master.stage.axes(1))*1000;
    master.stage.loc(2) = -coarseXYControl.qPOS (master.stage.axes(2))*1000;
    master.stage.loc(3) = coarseZControl.qPOS (master.stage.axes(3))*1000;
    master.stage.loc(4) = fineControl.qPOS (master.stage.axes(4));
    master.stage.loc(5) = fineControl.qPOS (master.stage.axes(5));
    master.stage.loc(6) = fineControl.qPOS (master.stage.axes(6));

    %Adds starting location to location record
    master.stage.locrecord = master.stage.loc;
    
    %Sets default values if not already present
    %Tolerance value for how far stage can be off of target
     if ~isfield(master.stage,'tolerance'),     master.stage.tolerance = .025;    end
     
     if ~isfield(master.stage,'recordOptVal'),     master.stage.recordOptVal = false;    end
     
     if ~isfield(master.stage,'recordOptLoc'),     master.stage.recordOptLoc = true;    end
     
     %Extra time waited for fine stage to complete its movement
     if ~isfield(master.stage,'finepause'),     master.stage.finepause = .01;    end
     
     %Extra time waited for coarse stages to complete their movement
     if ~isfield(master.stage,'coarsepause'),      master.stage.coarsepause = .1;     end

    %Sets initialization status to true
    master.stage.initialized = true;

    if master.notifications
        fprintf('PI stage successfully initialized\n')
    end

else
    if master.notifications
        fprintf("PI stage already initialized\n")
    end
end

end



