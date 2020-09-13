classdef GratingTemporal < edu.washington.riekelab.protocols.RiekeLabStageProtocol

    properties 
        amp
        preTime = 500                   % Pre-stimulus time
        waitTime = 500                  % Stationary grating display time
        stimTime = 4000                 % Grating motion time
        tailTime = 500                  % Post-stimulus time
        contrast = 1                    % Contrast (0-1)
        temporalFrequencies = [0.1, 0.2, 0.5, 1, 2, 5, 10, 20];   % Hz
        gratingClass = 'squarewave'     % Grating type
        direction = 0                   % Grating direction (degrees) 
        spatialFrequency = 2            % Cycles per short axis of screen
        backgroundIntensity = 0.5       % Mean light level (0-1)
        onlineAnalysis = 'none'         % Analysis type
        randomOrder = false             % Randomize epochs?
        numberOfAverages = uint16(36)   % Number of stimulus presentations
        interpulseInterval = 0
    end

    properties (Hidden)
        ampType
        gratingClassType = symphonyui.core.PropertyType('char', 'row',...
            {'none', 'squarewave', 'sinewave'});
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row',...
            {'none', 'extracellular', 'exc', 'inh'});
        
        allFrequencies
        temporalFrequency
        baseGrating 
    end

    properties (Hidden, Constant = true)
        DOWNSAMPLE = 3;
    end

    methods 
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end

        function p = getPreview(obj, panel)
            if isempty(obj.rig.getDevices('Stage'))
                p = [];
                return
            end
            p = io.github.stage_vss.previews.StagePreview(panel,...
                @()obj.createPresentation(),...
                'windowSize', obj.rig.getDevice('Stage').getCanvasSize());
        end

        function prepareRun(obj)
            prepareRun@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);

            if rem(obj.numberOfAverages, numel(obj.temporalFrequencies)) ~= 0
                error('numberOfAverages is not a factor of temporalFrequencies');
            end

            % Set temporal frequencies
            obj.allFrequencies = repmat(obj.temporalFrequencies,... 
                [1, obj.numberOfAverages / numel(obj.temporalFrequency)]);
            if obj.randomize 
                obj.allFrequencies = obj.allFrequencies(randperm(obj.numberOfAverages));
            end

            % Setup figures
            rgb = edu.washington.riekelab.patterson.utils.multigradient(...
                'preset', 'div.cb.spectral.9', 'length', numel(obj.temporalFrequencies));

            obj.showFigure('symphonyui.builtin.figures.ResponseFigure',...
                obj.rig.getDevice(obj.amp));
            obj.showFigure('edu.washington.riekelab.patterson.figures.MeanResponseFigure',...
                obj.rig.getDevice(obj.amp), 'groupBy', {'temporalFrequency'},...
                'recordingType', obj.onlineAnalysis, 'sweepColor', rgb);
            obj.showFigure('edu.washington.riekelab.patterson.figures.FrameTimingFigure',...
                obj.rig.getDevice('Stage'), obj.rig.getDevice('Frame Monitor'));
            if ~strcmp(obj.onlineAnalysis, 'none')
                obj.showFigure('edu.washington.riekelab.patterson.figures.F1F2Figure',...
                    obj.rig.getDevice(obj.amp), obj.temporalFrequencies, obj.onlineAnalysis,...
                    obj.preTime, obj.stimTime, 'waitTime', obj.waitTime,...
                    'xName', 'temporalFrequency', 'showF2', false);
            end
        end

        function p = createPresentation(obj)
            device = obj.rig.getDevice('Stage');
            canvasSize = device.getCanvasSize();

            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3);
            p.setBackgroundColor(obj.backgroundIntensity);

            grate = stage.builtin.stimuli.Image(uint8(0 * obj.rawImage));
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
                @(state)setDriftingGrating(obj, state.time - (obj.preTime + obj.waitTime) * 1e-3));
            p.addController(imgController);

            function g = setDriftingGrating(obj, time)
                if time >= 0
                    phase = obj.temporalFrequency * time * 2 * pi;
                else
                    phase = 0;
                end
                
                g = cos(phase + obj.rawImage);
                
                if strcmp(obj.spatialClass, 'squarewave')
                    g = sign(g);
                end
                
                g = obj.contrast * g;
                g = uint8(255*(obj.backgroundIntensity * g + obj.backgroundIntensity));
            end
        end

        function setGrating(obj)
            device = obj.rig.getDevice('Stage');
            canvasSize = device.getCanvasSize();
            sz = ceil(sqrt(canvasSize(1)^2 + canvasSize(2)^2));
            [x,y] = meshgrid(...
                linspace(-sz/2, sz/2, sz/obj.DOWNSAMPLE), ...
                linspace(-sz/2, sz/2, sz/obj.DOWNSAMPLE));
            
            x = x / min(canvasSize) * 2 * pi;
            y = y / min(canvasSize) * 2 * pi;

            img = (cos(0)*x + sin(0) * y) * obj.spatialFrequency;
            obj.baseGrating = repmat(img(1, :), [1, 1, 3]);
        end

        function prepareEpoch(obj, epoch)
            prepareEpoch@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj, epoch);
            
            device = obj.rig.getDevice(obj.amp);
            duration = (obj.preTime + obj.stimTime + obj.tailTime) / 1e3;
            epoch.addDirectCurrentStimulus(device, device.background, duration, obj.sampleRate);
            epoch.addResponse(device);

            obj.temporalFrequency = obj.allFrequencies(obj.numEpochsCompleted+1);
            epoch.addParameter('temporalFrequency');

            obj.setGrating();
        end

        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end

        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
        end
    end
end