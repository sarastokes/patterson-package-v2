classdef BarCentering < edu.washington.riekelab.protocols.RiekeLabStageProtocol
    
    properties
        amp                             % Output amplifier
        preTime = 250                   % Spot leading duration (ms)
        stimTime = 2000                 % Spot duration (ms)
        tailTime = 1000                 % Spot trailing duration (ms)
        intensity = 1.0                 % Bar intensity (0-1)
        temporalFrequency = 2.0         % Modulation frequency (Hz)
        barSize = [50 500]              % Bar size [width, height] (um)
        searchAxis = 'xaxis'            % Search axis
        temporalClass = 'squarewave'    % Squarewave or pulse?
        positions = -300:50:300         % Bar center position (um)
        backgroundIntensity = 0.5       % Background light intensity (0-1)
        centerOffset = [0,0]            % Center offset in pixels (x,y) 
        onlineAnalysis = 'none'         % Online analysis type.
        numberOfAverages = uint16(13)   % Number of epochs
        interpulseInterval = 0          % Duration between spots (s)
    end

    properties (Dependent, SetAccess = private)
        amp2
    end
    
    properties (Hidden)
        ampType
        searchAxisType = symphonyui.core.PropertyType('char', 'row',...
            {'xaxis', 'yaxis'})
        temporalClassType = symphonyui.core.PropertyType('char', 'row',...
            {'squarewave', 'sinewave'})
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row',...
            {'none', 'extracellular', 'exc', 'inh'})
        position                        % Current position in pixels
        orientation                     % Search axis in degrees
        sequence
        xaxis                           % Positions in microns
    end
    
    methods
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end
        
        function prepareRun(obj)
            prepareRun@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);

            % Create the matrix of bar positions.
            numReps = ceil(double(obj.numberOfAverages) / length(obj.positions));
            
            % Get the array of radii.
            pos = obj.positions(:) * ones(1, numReps);
            pos = pos(:);
            % Convert from um to pix
            pos = obj.rig.getDevice('Stage').um2pix(pos);
            obj.xaxis = pos';

            rgb = edu.washington.riekelab.patterson.utils.multigradient(...
                'preset', 'div.cb.spectral.9', 'length', numel(obj.positions));
            
            if numel(obj.rig.getDeviceNames('Amp')) < 2
                obj.showFigure('symphonyui.builtin.figures.ResponseFigure',...
                    obj.rig.getDevice(obj.amp));
                obj.showFigure('edu.washington.riekelab.patterson.figures.MeanResponseFigure',...
                    obj.rig.getDevice(obj.amp), 'groupBy', {'position'},...
                    'recordingType', obj.onlineAnalysis, 'sweepColor', rgb);
                if ~strcmp(obj.onlineAnalysis, 'none')
                    obj.showFigure('edu.washington.riekelab.patterson.figures.F1F2Figure',...
                        obj.rig.getDevice(obj.amp), obj.xaxis, obj.onlineAnalysis,...
                        obj.preTime, obj.stimTime, 'showF2', true,...
                        'temporalFrequency', obj.temporalFrequency,...
                        'xName', 'position'); 
                end
            else
                obj.showFigure('edu.washington.riekelab.figures.DualResponseFigure',...
                    obj.rig.getDevice(obj.amp), obj.rig.getDevice(obj.amp2));
            end
            
            if strcmp(obj.searchAxis, 'xaxis')
                obj.orientation = 0;
                obj.sequence = [pos+obj.centerOffset(1) obj.centerOffset(2)*ones(length(pos),1)];
            else
                obj.orientation = 90;
                obj.sequence = [obj.centerOffset(1)*ones(length(pos),1) pos+obj.centerOffset(2)];
            end
        end
        
        function p = createPresentation(obj)
            device = obj.rig.getDevice('Stage');
            canvasSize = device.getCanvasSize();
            
            barSizePix = device.um2pix(obj.barSize);
            
            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3);
            p.setBackgroundColor(obj.backgroundIntensity);
            
            rect = stage.builtin.stimuli.Rectangle();
            rect.size = barSizePix; 
            rect.orientation = obj.orientation;
            rect.position = canvasSize/2 + obj.position;
            rect.color = obj.intensity*obj.backgroundIntensity + obj.backgroundIntensity;
            p.addStimulus(rect);       
            
            % Control when the spot is visible.
            spotVisible = stage.builtin.controllers.PropertyController(rect, 'visible', ...
                @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
            p.addController(spotVisible);
            
            % Control the bar intensity.
            if strcmp(obj.temporalClass, 'squarewave')
                colorController = stage.builtin.controllers.PropertyController(rect, 'color', ...
                    @(state)getBarSquarewave(obj, state.time - obj.preTime * 1e-3));
            else
                colorController = stage.builtin.controllers.PropertyController(rect, 'color',...
                    @(state)getBarSinewave(obj, state.time - obj.preTime * 1e-3));
            end
            p.addController(colorController);
            
            function c = getBarSquarewave(obj, time)       
                    c = obj.intensity * sign(sin(obj.temporalFrequency*time*2*pi)) * obj.backgroundIntensity + obj.backgroundIntensity;
            end
            
            function c = getBarSinewave(obj, time)
                c = obj.intensity * sin(obj.temporalFrequency*time*2*pi) * obj.backgroundIntensity + obj.backgroundIntensity;
            end
            
        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj, epoch);
            
            device = obj.rig.getDevice(obj.amp);
            duration = (obj.preTime + obj.stimTime + obj.tailTime) / 1e3;
            epoch.addDirectCurrentStimulus(device, device.background, duration, obj.sampleRate);
            epoch.addResponse(device);

            obj.position = obj.sequence(obj.numEpochsCompleted+1, :);
            if strcmp(obj.searchAxis, 'xaxis')
                epoch.addParameter('position', obj.position(1));
            else
                epoch.addParameter('position', obj.position(2));
            end
        end

        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end

        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
        end
                
        function a = get.amp2(obj)
            amps = obj.rig.getDeviceNames('Amp');
            if numel(amps) < 2
                a = '(None)';
            else
                i = find(~ismember(amps, obj.amp), 1);
                a = amps{i};
            end
        end
    end
end