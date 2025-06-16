classdef cam < instrumentType
   
   properties
      camera
      source
      bounds %rows, columns (not x,y)
      outputFullImage = true;
      outputFrameStack = true;
   end

   properties (Dependent)
      %Stored in camera/source object
      exposureTime
      defectCorrectionEnabled
      defectCorrectionLevel
      framesPerTrigger
   end

   properties (SetAccess = {?cam ?instrumentType}, GetAccess = public)
      %Read-only for user (derived from config)
      manufacturer
      imageType
   end

   methods

      function obj = cam(configFileName)
         %Creates cam object

         if nargin < 1
            error('Config file name required as input')
         end

         %Loads config file and checks relevant field names
         configFields = {'manufacturer','imageType','defaults'};
         commandFields = {};
         numericalFields = {};
         obj = loadConfig(obj,configFileName,configFields,commandFields,numericalFields);

         %Set identifier as given name
         obj.identifier = 'Hamamatsu';
      end
      
      function delete(obj)
      %What happens when the object is deleted
      %Turn off camera if possible before clearing object
         if ~isempty(obj.camera)
            try
            stop(obj.camera)
            catch
            end
         end
      end

      function obj = connect(obj)
         try
         %Creates the connection to the camera and its source
         obj.camera = videoinput(obj.manufacturer,1,obj.imageType);
         obj.source = getselectedsource(obj.camera);
         obj.connected = true;

         %Overrides only the values that aren't already set with either
         %their preset or default value
         obj = instrumentType.overrideStruct(obj,checkSettings(obj,fieldnames(obj.presets)));
         
         %Sets logging to RAM allocated to MatLab rather than saving to
         %disk which takes longer and makes a file
         obj.camera.LoggingMode = 'memory';
         
         %When triggered, immediately takes frames
         triggerconfig(obj.camera, 'immediate');
         
         %Sets the camera to an active state, ready to be triggered
         start(obj.camera)
         
         printOut(obj,'Camera Connected')
         catch ME
            obj.connected = false;
            rethrow(ME)
         end
      end
      
      function [averageImages,frameStacks] = takeImage(obj)
         checkConnection(obj)
         
         %This block of code is used to prevent the camera from ever
         %getting a frame value above 100 (which would cause an error). I
         %am dividing the total frames into sets of 100 and an additional
         %last set of whatever the leftover value is
         storedFPT = obj.camera.FramesPerTrigger;
         nsets = ceil(obj.camera.FramesPerTrigger /100);
         lastset = mod(obj.camera.FramesPerTrigger,100);
         obj.framesPerTrigger = 100;
         
         for kk = 1:nsets
            %If this is the last set, change the frames per trigger to be
            %whatever the leftover value is
            if kk == nsets
               obj.camera.FramesPerTrigger = lastset;
            end
            
            %Tells camera to take frames
            trigger(obj.camera)
            
            %Obtains data from camera
            totalImageOut = getdata(obj.camera);
            
            %Converts to 3D array. Unsure why a 4th is created in the first place
            totalImageOut = double(squeeze(totalImageOut));

            %Preallocation for full frame stack after getting image size
            if kk == 1
               totalFrames = zeros(size(totalImageOut,1),size(totalImageOut,1),storedFPT);
            end
            
            %Assigns image to the correct spot
            totalFrames(:,:,1+100*(kk-1):100*kk) = totalImageOut;
            
         end

         %Get number of expected output images
         nOutputs = getNumberOfImageOutputs(obj,size(totalFrames(:,:,1)));
         
         %For each set of bounds, take the overall frame stack and cut it
         %down to the correct bounds. Then take the average of that cut
         %image to output
         for ii = 1:numel(obj.useBounds)
            cutFrameStack = totalFrames(obj.bounds{ii,1}(1):obj.bounds{ii,1}(2),obj.bounds{ii,2}(1):obj.bounds{ii,2}(2),:);
            averageImages{ii} = mean(cutFrameStack,3); %#ok<AGROW>
            if obj.outputFrameStack
               frameStacks{ii} = cutFrameStack; %#ok<AGROW>               
            end        
         end

         %If number of outputs and number of bounds are not the same, an additional set of images will be added that is
         %for the entire image
         if numel(obj.useBounds) ~= nOutputs
            averageImages{end+1} = mean(totalFrames,3);
            if obj.outputFrameStack
               frameStacks{end+1} = totalFrames;
            end
         end

         %Adds empty output for frameStacks if outputFrameStack is off
         if ~obj.outputFrameStack
            frameStacks = [];
         end
         
         %Sets frames back to original
         obj.framesPerTrigger = storedFPT;
         
      end
      
      function obj = boundSelector(obj)
         checkConnection(obj)
         
         %Saves previous camera settings
         oldFramesPerTrigger = obj.camera.FramesPerTrigger;
         obj.camera.FramesPerTrigger = 1;
         oldFullImage = obj.outputFullImage;
         obj.outputFullImage = true;

         %Deletes previous bounds
         obj.bounds = {};
         
         %Takes image that will be used to select the bounds
         totalIm = takeImage(obj);
         
         %Resets camera settings back to what they were originally
         obj.camera.FramesPerTrigger = oldFramesPerTrigger;
         obj.outputFullImage = oldFullImage;
         
         %Two while loops. External loop is for selecting different sets of
         %bounds. Internal loop is for ensuring the bounds selected are
         %correct
         moreBounds = true;
         n = 1;
         while moreBounds
            
            correctBounds = false;
            while ~correctBounds
               %Creates figure with image that was taken
               figure('Name','Bounds Selector','NumberTitle','off');
               imagesc(totalIm);
               colormap(gray)
               
               %User selects a region within the image and the vertices of
               %that region are used to get the row/column bounds
               title('Please draw a rectangle around the desired area')
               roi = drawrectangle;
               rowBound = [round(roi.Vertices(1,2)) round(roi.Vertices(2,2))];
               colBound = [round(roi.Vertices(1,1)) round(roi.Vertices(3,1))];
               close('Bounds Selector')
               
               %Creates an image with the new bounds for confirmation
               figure('Name','Bounds Confirmation','NumberTitle','off');
               imagesc(totalIm(rowBound(1):rowBound(2),colBound(1):colBound(2)))
               colormap(gray)
               
               %If bounds are correct, break out of loop, otherwise restart
               %process
               correctBounds = strcmp(questdlg('Are these bounds correct?', 'Yes', 'No'),'Yes');
               close('Bounds Confirmation')
            end
            
            %Saves the selected bounds to the cam object
            %nx2 cell array where first column is for row bounds and second
            %is for column bounds
            obj.bounds{n,1} = rowBound;
            obj.bounds{n,2} = colBound;
            
            %If more bounds are desired, restart process and increment
            %counting variable
            boundsMessage = sprintf('Do you want to select another set of bounds? Current total is %d',n);
            moreBounds = strcmp(questdlg(boundsMessage,'Yes', 'No'),'Yes');
            n = n+1;
         end
      end
      
      function blankOutput = generateBlankOutput(obj,varargin)
         %Creates a blank output based on the current bounds and settings
         %2nd argument is the full image size

         blankOutput = {};

         %For each set of bounds, find the x and y range then make a matrix
         %of zeros according to that size
         for ii = 1:numel(obj.bounds)
            xRange = 1 + ex.hamm.bounds{ii,2}(2) - ex.hamm.bounds{ii,2}(1);
            yRange = 1+ ex.hamm.bounds{ii,1}(2) - ex.hamm.bounds{ii,1}(1);
            blankOutput{end+1} = zeros(yRange,xRange); %#ok<AGROW>
         end

         %Adds another matrix the size of the full image if it is enabled
         if obj.outputFullImage            
            if nargin == 1
               error('Full image size (2nd argument) must be included if outputFullImage is enabled')
            end
            fullImageSize = varargin{1};
            blankOutput{end+1} = zeros(fullImageSize(1),fullImageSize(2));
         end

         %Repeat for frame stack if enabled
         if obj.outputFrameStack
            for ii = 1:numel(obj.bounds)
               xRange = ex.hamm.bounds{ii,2}(2) - ex.hamm.bounds{ii,2}(1);
               yRange = ex.hamm.bounds{ii,1}(2) - ex.hamm.bounds{ii,1}(1);
               blankOutput{end+1} = zeros(yRange,xRange,obj.framesPerTrigger); %#ok<AGROW>
            end
            if obj.outputFullImage
               blankOutput{end+1} = zeros(fullImageSize(1),fullImageSize(2),obj.framesPerTrigger);
            end
         end

      end

      function nOutputs = getNumberOfImageOutputs(obj,totalSize)
         %Find number of outputs that will be present based on number of bounds and whether those bounds match the full
         %image

         nOutputs = size(obj.bounds,1);

         %If outputFullImage is off, number of outputs will just be number of bounds
         if ~obj.outputFullImage
            return
         end

         %Checks each set of bounds to see if it matches the total size
         hasMaxSizeBounds  = false;
         for ii = 1:nOutputs
            if all([obj.bounds{ii,1}(1),obj.bounds{ii,1}(2);obj.bounds{ii,2}(1),obj.bounds{ii,2}(2)] == [1,size(totalSize,1);1,size(totalSize,2)])
               hasMaxSizeBounds  = true;
            end
         end

         %If nothing matches the max size bounds (and outputFullImage is true), add 1 output
         if ~hasMaxSizeBounds
            nOutputs = nOutputs + 1;
         end
      end

   end

   %% Dependent Property Functions
   methods 
      %These functions make sure that there are no desyncing errors.

      %I normally create a property for each value that can be changed.
      %However, since e.g. "exposureTime" is set within the "source"
      %property, I cannot just make another variable for exposureTime
      %because it will not be the same as the real value within source.
      %Thus, I make exposureTime dependent on the value within source,
      %circumnavigating this issue
      function obj = setParameter(obj,val,varName,internalName)         
         if obj.connected
            obj.source.(internalName) = val;
         else
            obj.presets.(varName) = val;
         end
      end
      function val = getParameter(obj,varName,internalName)
         if obj.connected
            val = obj.source.(internalName);
         elseif isfield(obj.presets,varName) && ~isempty(obj.presets.(varName))
            val = obj.presets.(varName);
         elseif isfield(obj.defaults,varName) && ~isempty(obj.defaults.(varName))
            val = obj.defaults.(varName);
         else
            val  =[];
         end
      end      

      function set.exposureTime(obj,val)
         obj = setParameter(obj,val,'exposureTime','ExposureTime'); %#ok<NASGU>
      end
      function val = get.exposureTime(obj)
         val = setParameter(obj,'exposureTime','ExposureTime');
      end

      function set.defectCorrectionEnabled(obj,val)
         obj = setParameter(obj,val,'defectCorrectionEnabled','DefectCorrect'); %#ok<NASGU>
      end
      function val = get.defectCorrectionEnabled(obj)
         val = setParameter(obj,'defectCorrectionEnabled','DefectCorrect');
      end

      function set.defectCorrectionLevel(obj,val)
         obj = setParameter(obj,val,'defectCorrectionLevel','HotPixelCorrectionLevel'); %#ok<NASGU>
      end
      function val = get.defectCorrectionLevel(obj)
         val = setParameter(obj,'defectCorrectionLevel','HotPixelCorrectionLevel');
      end

      %FramesPerTrigger is in camera not in source
      function set.framesPerTrigger(obj,val)
         if obj.connected
            obj.camera.FramesPerTrigger = val;
         else
            obj.presets.framesPerTrigger = val;
         end
      end
      function val = get.framesPerTrigger(obj)
         varName = 'framesPerTrigger';
         if obj.connected
            val = obj.camera.FramesPerTrigger;
         elseif isfield(obj.presets,varName) && ~isempty(obj.presets.(varName))
            val = obj.presets.(varName);
         elseif isfield(obj.defaults,varName) && ~isempty(obj.defaults.(varName))
            val = obj.defaults.(varName);
         else 
            val = [];
         end
      end

   end

end