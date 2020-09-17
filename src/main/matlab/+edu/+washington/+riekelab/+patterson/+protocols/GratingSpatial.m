classdef GratingSpatial < edu.washington.riekelab.protocols.RiekeLabStageProtocol

    properties 
        amp
        preTime = 500                   % Pre-stimulus time
        waitTime = 500                  % Stationary grating display time
        stimTime = 4000                 % Grating motion time
        tailTime = 500                  % Post-stimulus time
        contrast = 1                    % Contrast (0-1)
        temporalFrequency = 2;          % Hz
        gratingClass = 'squarewave'     % Grating type
        direction = 0                   % Grating direction (degrees) 
        spatialFrequencies = [0.5, 1, 2, 5, 10, 15, 20]  % Cycles per short axis of screen
        apertureDiameter = 0            % Aperture diameter (pixels)
        backgroundIntensity = 0.5       % Mean light level (0-1)
        onlineAnalysis = 'none'         % Analysis type
        randomOrder = false             % Randomize epochs?
        numberOfAverages = uint16(36)   % Number of stimulus presentations
    end

    properties (Hidden)
        ampType
        gratingClassType = symphonyui.core.PropertyType('char', 'row',...
            {'none', 'squarewave', 'sinewave'});
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row',...
            {'none', 'extracellular', 'exc', 'inh'});
        
        allFrequencies
        spatialFrequency
        baseGrating 
    end

    methods 
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end

        function prepareRun(obj)
            prepareRun@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);

            % Input checking
            if rem(obj.numberOfAverages, numel(obj.spatialFrequencies)) ~= 0
                error('numberOfAverages is not a factor of spatialFrequencies');
            end

            % Set spatial frequencies
            obj.allFrequencies = repmat(obj.spatialFrequencies,... 
                [1, obj.numberOfAverages / numel(obj.spatialFrequency)]);
            if obj.randomize 
                obj.allFrequencies = obj.allFrequencies(randperm(obj.numberOfAverages));
            end

            % Setup figures
            rgb = edu.washington.riekelab.patterson.utils.multigradient(...
                'preset', 'div.cb.spectral.9',... 
                'length', numel(unique(obj.spatialFrequencies)));

            obj.showFigure('symphonyui.builtin.figures.ResponseFigure',...
                obj.rig.getDevice(obj.amp));
            obj.showFigure('edu.washington.riekelab.patterson.figures.MeanResponseFigure',...
                obj.rig.getDevice(obj.amp), 'groupBy', {'spatialFrequency'},...
                'recordingType', obj.onlineAnalysis, 'sweepColor', rgb);
            obj.showFigure('edu.washington.riekelab.patterson.figures.FrameTimingFigure',...
                obj.rig.getDevice('Stage'), obj.rig.getDevice('Frame Monitor'));

            if ~strcmp(obj.onlineAnalysis, 'none')
                obj.showFigure('edu.washington.riekelab.patterson.figures.F1F2Figure',...
                    obj.rig.getDevice(obj.amp), obj.onlineAnalysis,...
                    obj.preTime, obj.stimTime, 'WaitTime', obj.waitTime,...
                    'TemporalFrequency', obj.temporalFrequency,...
                    'VariedParameterName', 'spatialFrequency',...
                    'GraphName', 'Spatial Frequency Tuning');
            end
        end

        function p = createPresentation(obj)
            device = obj.rig.getDevice('Stage');
            canvasSize = device.getCanvasSize();
            centerOffsetPix = obj.rig.getDevice('Stage').um2pix(obj.centerOffset);

            p = stage.core.Presentation((obj.preTime + obj.waitTime + obj.stimTime + obj.tailTime) * 1e-3);
            p.setBackgroundColor(obj.backgroundIntensity);

            grate = stage.builtin.stimuli.Image(uint8(0 * obj.baseGrating));
            grate.position = canvasSize / 2;
            grate.size = ceil(sqrt(canvasSize(1)^2 + canvasSize(2)^2))*ones(1,2);
            grate.orientation = obj.direction;
            grate.setMinFunction(GL.NEAREST);
            grate.setMagFunction(GL.NEAREST);
            p.addStimulus(grate);
            
            grateVisible = stage.builtin.controllers.PropertyController(grate, 'visible', ...
                @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
            p.addController(grateVisible);

            imgController = stage.builtin.controllers.PropertyController(grate, 'imageMatrix',...
                @(state)getGratingDrift(obj, state.time - (obj.preTime + obj.waitTime) * 1e-3));
            p.addController(imgController);

            if obj.apertureDiameter > 0
                aperture = stage.builtin.stimuli.Rectangle();
                aperture.position = canvasSize/2 + centerOffsetPix;
                aperture.color = obj.backgroundIntensity;
                aperture.size = 2 * max(canvasSize) * ones(1, 2);
                mask = stage.core.Mask.createCircularAperture(...
                    obj.apertureDiameter / (2 * max(canvasSize)));
                aperture.setMask(mask);
                p.addStimulus(aperture);
            end

            function g = getGratingDrift(obj, time)
                if time >= 0
                    phase = obj.temporalFrequency * time * 2 * pi;
                else
                    phase = 0;
                end
                
                g = cos(phase + obj.baseGrating);
                
                if strcmp(obj.gratingClass, 'squarewave')
                    g = sign(g);
                end
                
                g = obj.contrast * g;
                g = uint8(255*(obj.backgroundIntensity * g + obj.backgroundIntensity));
            end
        end

        function getBaseGrating(obj)
            device = obj.rig.getDevice('Stage');
            canvasSize = device.getCanvasSize();
            sz = ceil(sqrt(canvasSize(1)^2 + canvasSize(2)^2));
            [x,y] = meshgrid(...
                linspace(-sz/2, sz/2, sz), ...
                linspace(-sz/2, sz/2, sz));
            
            x = x / min(canvasSize) * 2 * pi;
            y = y / min(canvasSize) * 2 * pi;

            img = (cos(0)*x + sin(0) * y) * obj.spatialFrequency;
            obj.baseGrating = repmat(img(1, :), [1, 1, 3]);
        end

        function prepareEpoch(obj, epoch)
            prepareEpoch@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj, epoch);
            
            device = obj.rig.getDevice(obj.amp);
            duration = (obj.preTime + obj.waitTime + obj.stimTime + obj.tailTime) / 1e3;
            epoch.addDirectCurrentStimulus(device, device.background, duration, obj.sampleRate);
            epoch.addResponse(device);

            obj.spatialFrequency = obj.allFrequencies(obj.numEpochsCompleted+1);
            epoch.addParameter('spatialFrequency')

            obj.setBaseGrating();
        end

        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end

        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
        end
    end
end