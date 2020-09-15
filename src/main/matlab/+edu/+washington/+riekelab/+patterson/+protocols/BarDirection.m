classdef BarDirection < edu.washington.riekelab.protocols.RiekeLabProtocol

    properties 
        amp 
        preTime = 500                   % Time preceding stimulus (ms)
        stimTime = 2500                 % Time window for bar presentation (ms)
        tailTime = 500                  % Time after stimulus window (ms)
        directions = 0:30:330           % Bar angle (degrees)
        speed = 500                     % Bar speed (microns/sec)
        contrast = 1.0                  % Bar contrast/intensity (0-1)
        barSize = [120, 240]            % Bar size width and height (microns)
        backgroundIntensity = 0.5       % Mean light intensity (0-1)
        apertureDiameter = 500          % Aperture diameter (microns)
        randomize = false               % Randomize directions?
        numberOfAverages = uint16(36)   % Number of epochs
    end

    properties (Hidden)
        ampType
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row',...
            {'none', 'extracellular', 'exc', 'inh'});
        direction
        allDirections
        barIntensity
    end

    methods
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end

        function prepareRun(obj)
            prepareRun@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);

            % Input checking
            if rem(obj.numberOfAverages, numel(obj.directions)) ~= 0
                error('numberOfAverages is not a factor of directions');
            end

            if obj.rig.getDevice('Stage').um2pix(obj.apertureDiameter) > min(obj.rig.getDevice('Stage').getCanvasSize())
                error('apertureDiameter exceeds minimum canvasSize');
            end

            % Set) directions for each epoch
            obj.allDirections = repmat(obj.directions,... 
                [1, obj.numberOfAverages / numel(obj.directions)]);
            if obj.randomize 
                obj.allDirections = obj.allDirections(randperm(obj.numberOfAverages));
            end

            % Account for both mean and zero mean options
            if obj.backgroundIntensity > 0
                obj.barIntensity = obj.backgroundIntensity * obj.contrast + obj.backgroundIntensity;
            else
                obj.barIntensity = obj.contrast;
            end

            % Set up figures
            rgb = edu.washington.riekelab.patterson.utils.multigradient(...
                'preset', 'div.cb.spectral.9', 'length', numel(obj.directions));

            obj.showFigure('symphonyui.builtin.figures.ResponseFigure',...
                obj.rig.getDevice(obj.amp));
            obj.showFigure('edu.washington.riekelab.patterson.figures.MeanResponseFigure',...
                obj.rig.getDevice(obj.amp), 'groupBy', {'direction'},...
                'recordingType', obj.onlineAnalysis, 'sweepColor', rgb);
            obj.showFigure('edu.washington.riekelab.patterson.figures.FrameTimingFigure',...
                obj.rig.getDevice('Stage'), obj.rig.getDevice('Frame Monitor'));     
        end

        function p = createPresentation(obj)
            canvasSize = obj.rig.getDevice('Stage').getCanvasSize();
            centerOffsetPix = obj.rig.getDevice('Stage').um2pix(obj.centerOffset);
            
            speedPix = obj.rig.getDevice('Stage').um2pix(obj.speed);
            barSizePix = obj.rig.getDevice('Stage').um2pix(obj.barSize);
            apertureDiameterPix = obj.rig.getDevice('Stage').um2pix(obj.apertureDiameter);

            directionRads = deg2rad(obj.direction);
            
            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3); 
            p.setBackgroundColor(obj.backgroundIntensity);

            % Create bar
            rect = stage.builtin.stimuli.Rectangle();
            rect.size = barSizePix;
            rect.position = canvasSize/2 + centerOffsetPix;
            rect.orientation = obj.direction;
            rect.color = obj.barIntensity;
            p.addStimulus(rect);

            barVisible = stage.builtin.controllers.PropertyController(rect, 'visible', ...
                @(state)state.time >= obj.preTime * 1e-3...
                && state.time < (obj.preTime + obj.stimTime) * 1e-3);
            p.addController(barVisible);

            barPosition = stage.builtin.controllers.PropertyController(rect, 'position', ...
                @(state)getBarPosition(obj, state.time - obj.preTime*1e-3));
            p.addController(barPosition);

            % Create aperture
            if obj.apertureDiameter > 0
                aperture = stage.builtin.stimuli.Rectangle();
                aperture.position = canvasSize/2 + centerOffsetPix;
                aperture.color = obj.backgroundIntensity;
                aperture.size = 2 * max(canvasSize) * ones(1, 2);
                mask = stage.core.Mask.createCircularAperture(...
                    apertureDiameterPix / (2 * max(canvasSize)));
                aperture.setMask(mask);
                p.addStimulus(aperture);
            else
                apertureDiameterPix = max(canvasSize);
            end

            function p = getBarPosition(~, time)
                inc = time * speedPix - (apertureDiameterPix / 2) - barSizePix(1)/2;
                p = [cos(directionRads) sin(directionRads)] ...
                    .* (inc * ones(1,2)) + canvasSize/2 + centerOffsetPix;
            end
        end

        function prepareEpoch(obj, epoch)
            prepareEpoch@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj, epoch);

            device = obj.rig.getDevice(obj.amp);
            duration = (obj.preTime + obj.stimTime + obj.tailTime) / 1e3;
            epoch.addDirectCurrentStimulus(device, device.background, duration, obj.sampleRate);
            epoch.addResponse(device);
            
            obj.direction = obj.allDirections(obj.numEpochsCompleted + 1);
            epoch.addParameter('direction', obj.direction);
        end

        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end

        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
        end
    end
end 