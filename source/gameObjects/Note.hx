package gameObjects;

import flixel.FlxG;
import flixel.math.FlxPoint;
import flixel.FlxSprite;
import flixel.graphics.frames.FlxAtlasFrames;
import flixel.math.FlxMath;
import flixel.util.FlxColor;
import flash.display.BitmapData;
import meta.states.editors.ChartingState;
import meta.data.*;
import meta.states.*;
import openfl.utils.AssetType;
import openfl.utils.Assets;
import meta.data.scripts.*;
import gameObjects.shader.*;
import math.Vector3;
#if sys
import sys.FileSystem;
#end
using StringTools;

typedef EventNote = {
	strumTime:Float,
	event:String,
	value1:String,
	value2:String
}

class Note extends FlxSprite
{
	public var row:Int = 0;

	public var noteScript:FunkinScript;

	public static var quants:Array<Int> = [
		4, // quarter note
		8, // eight
		12, // etc
		16,
		20,
		24,
		32,
		48,
		64,
		96,
		192
	];

	public var vec3Cache:Vector3 = new Vector3(); // for vector3 operations in modchart code
	public var defScale:FlxPoint = FlxPoint.get(); // for modcharts to keep the scaling

	public var mAngle:Float = 0;
	public var bAngle:Float = 0;

	public var typeOffsetX:Float = 0; // used to offset notes, mainly for note types. use in place of offset.x and offset.y when offsetting notetypes
	public var typeOffsetY:Float = 0;

	public static function getQuant(beat:Float){
		var row = Conductor.beatToNoteRow(beat);
		for(data in quants){
			if(row%(Conductor.ROWS_PER_MEASURE/data) == 0){
				return data;
			}
		}
		return quants[quants.length-1]; // invalid
	}
	public var noteDiff:Float = 1000;
	public var quant:Int = 4;
	public var zIndex:Float = 0;
	public var desiredZIndex:Float = 0;
	public var z:Float = 0;
	public var garbage:Bool = false; // if this is true, the note will be removed in the next update cycle
	public var alphaMod:Float = 1;
	public var alphaMod2:Float = 1; // TODO: unhardcode this shit lmao

	public var extraData:Map<String,Dynamic> = [];
	public var hitbox:Float = Conductor.safeZoneOffset;
	public var isQuant:Bool = false; // mainly for color swapping, so it changes color depending on which set (quants or regular notes)
	public var canQuant:Bool = true;
	public var strumTime:Float = 0;

	public var mustPress:Bool = false;
	public var noteData:Int = 0;
	public var canBeHit:Bool = false;
	public var tooLate:Bool = false;
	public var wasGoodHit:Bool = false;
	public var ignoreNote:Bool = false;
	public var hitByOpponent:Bool = false;
	public var noteWasHit:Bool = false;
	public var prevNote:Note;
	public var nextNote:Note;

	public var spawned:Bool = false;

	public var tail:Array<Note> = []; // for sustains
	public var parent:Note;

	public var sustainLength:Float = 0;
	public var isSustainNote:Bool = false;
	public var noteType(default, set):String = null;

	public var eventName:String = '';
	public var eventLength:Int = 0;
	public var eventVal1:String = '';
	public var eventVal2:String = '';

	public var colorSwap:ColorSwap;
	public var inEditor:Bool = false;
	public var gfNote:Bool = false;
	public var baseScaleX:Float = 1;
	public var baseScaleY:Float = 1;

	private var earlyHitMult:Float = 0.5;

	@:isVar
	public var daWidth(get, null):Float;

	public function get_daWidth()
	{
		return playField == null ? Note.swagWidth : playField.swagWidth;
	}

	public static var swagWidth:Float = 160 * 0.7;
	public static var PURP_NOTE:Int = 0;
	public static var GREEN_NOTE:Int = 2;
	public static var BLUE_NOTE:Int = 1;
	public static var RED_NOTE:Int = 3;

	// Lua shit
	public var noteSplashDisabled:Bool = false;
	public var noteSplashTexture:String = null;
	public var noteSplashHue:Float = 0;
	public var noteSplashSat:Float = 0;
	public var noteSplashBrt:Float = 0;

	public var offsetX:Float = 0;
	public var offsetY:Float = 0;
	public var offsetAngle:Float = 0;
	public var multAlpha:Float = 1;
	public var multSpeed(default, set):Float = 1;

	public var copyX:Bool = true;
	public var copyY:Bool = true;
	public var copyAngle:Bool = true;
	public var copyAlpha:Bool = true;

	public var hitHealth:Float = 0.035;
	public var missHealth:Float = 0.08;
	public var rating:String = 'unknown';
	public var ratingMod:Float = 0; //9 = unknown, 0.25 = shit, 0.5 = bad, 0.75 = good, 1 = sick
	public var ratingDisabled:Bool = false;

	public var texture(default, set):String = null;

	public var noAnimation:Bool = false;
	public var noMissAnimation:Bool = false;
	public var hitCausesMiss:Bool = false;
	public var distance:Float = 2000; //plan on doing scroll directions soon -bb

	public var hitsoundDisabled:Bool = false;

	public var player:Int = 0;

	public var playField(default, set):PlayField;
	public var desiredPlayfield:PlayField; // incase a note should be put into a specific playfield
	public static var defaultNotes = [
		'No Animation',
		'GF Sing',
		''
	];

	public function set_playField(field:PlayField){
		if(playField!=field){
			if(playField!=null && playField.notes.contains(this))
				playField.remNote(this);

			if(field!=null && !field.notes.contains(this))
				field.addNote(this);
			
		}
		return playField = field;
	}

	private function set_multSpeed(value:Float):Float {
		resizeByRatio(value / multSpeed);
		multSpeed = value;
		// trace('fuck cock');
		return value;
	}

	public function resizeByRatio(ratio:Float) //haha funny twitter shit
	{
		if(isSustainNote && !animation.curAnim.name.endsWith('end'))
		{
			scale.y *= ratio;
			baseScaleY = scale.y;
			updateHitbox();
		}
	}

	private function set_texture(value:String):String {
		if(texture != value) {
			reloadNote('', value);
		}
		texture = value;
		return value;
	}

	private function set_noteType(value:String):String {
		noteSplashTexture = PlayState.SONG.splashSkin;
		if(isQuant && ClientPrefs.data.noteSkin == "Quants"){
			var idx = quants.indexOf(quant);
			colorSwap.hue = ClientPrefs.data.quantHSV[idx][0] / 360;
			colorSwap.saturation = ClientPrefs.data.quantHSV[idx][1] / 100;
			colorSwap.brightness = ClientPrefs.data.quantHSV[idx][2] / 100;
			if (noteSplashTexture == 'noteSplashes' || noteSplashTexture.length <= 0 || PlayState.SONG.splashSkin==null)noteSplashTexture = 'QUANTnoteSplashes'; // give it da quant notesplashes!!
		}else if(isQuant && ClientPrefs.data.noteSkin == "QuantStep"){
			var idx = quants.indexOf(quant);
			colorSwap.hue = ClientPrefs.data.quantStepmania[idx][0] / 360;
			colorSwap.saturation = ClientPrefs.data.quantStepmania[idx][1] / 100;
			colorSwap.brightness = ClientPrefs.data.quantStepmania[idx][2] / 100;
			if (noteSplashTexture == 'noteSplashes' || noteSplashTexture.length <= 0 || PlayState.SONG.splashSkin==null)noteSplashTexture = 'QUANTnoteSplashes'; // give it da quant notesplashes!!

		}
		else{
			colorSwap.hue = ClientPrefs.data.arrowHSV[noteData % 4][0] / 360;
			colorSwap.saturation = ClientPrefs.data.arrowHSV[noteData % 4][1] / 100;
			colorSwap.brightness = ClientPrefs.data.arrowHSV[noteData % 4][2] / 100;
		}

		noteScript = null;

		if(noteData > -1 && noteType != value) {
			switch(value) {
				case 'Hurt Note':
					ignoreNote = mustPress;
					reloadNote('HURT');
					noteSplashTexture = 'HURTnoteSplashes';
					colorSwap.hue = 0;
					colorSwap.saturation = 0;
					colorSwap.brightness = 0;
					if(isSustainNote) {
						missHealth = 0.1;
					} else {
						missHealth = 0.3;
					}
					hitCausesMiss = true;

				case 'No Animation':
					noAnimation = true;
					noMissAnimation = true;
				case 'GF Sing':
					gfNote = true;
				case 'Ghost Note':
					alpha = 0.8;
					color = 0xffa19f9f;
				default:
					if (!inEditor)
						noteScript = PlayState.instance.notetypeScripts.get(value);
					else
						noteScript = ChartingState.instance.notetypeScripts.get(value);
					
					if (noteScript != null && noteScript.scriptType == 'hscript')
					{
						var noteScript:FunkinHScript = cast noteScript;
						noteScript.executeFunc("setupNote", [this], this);
					}
						
			}
			noteType = value;
		}
		noteSplashHue = colorSwap.hue;
		noteSplashSat = colorSwap.saturation;
		noteSplashBrt = colorSwap.brightness;
		return value;
	}

	public function new(strumTime:Float, noteData:Int, ?prevNote:Note, ?sustainNote:Bool = false, ?inEditor:Bool = false, ?player:Int = 0)
	{
		super();

		if (prevNote == null)
			prevNote = this;


		this.prevNote = prevNote;
		this.player = player;
		isSustainNote = sustainNote;


		if ((ClientPrefs.data.noteSkin == 'Quants' || ClientPrefs.data.noteSkin == "QuantStep") && canQuant){
			var beat = Conductor.getBeatInMeasure(strumTime);
			if(prevNote!=null && isSustainNote)
				quant = prevNote.quant;
			else
				quant = getQuant(beat);
		}
		this.inEditor = inEditor;

		x += (ClientPrefs.data.middleScroll ? PlayState.STRUM_X_MIDDLESCROLL : PlayState.STRUM_X) + 50;
		// MAKE SURE ITS DEFINITELY OFF SCREEN?
		y -= 2000;
		this.strumTime = strumTime;
		if(!inEditor) this.strumTime += ClientPrefs.data.noteOffset;

		this.noteData = noteData;

		if(noteData > -1) {
			texture = '';
			colorSwap = new ColorSwap();
			shader = colorSwap.shader;

			x += swagWidth * (noteData % 4);
			if(!isSustainNote) { //Doing this 'if' check to fix the warnings on Senpai songs
				var animToPlay:String = '';
				switch (noteData % 4)
				{
					case 0:
						animToPlay = 'purple';
					case 1:
						animToPlay = 'blue';
					case 2:
						animToPlay = 'green';
					case 3:
						animToPlay = 'red';
				}
				animation.play(animToPlay + 'Scroll');
			}
		}

		// trace(prevNote);

		if(prevNote!=null)
			prevNote.nextNote = this;

		if (isSustainNote && prevNote != null)
		{
			alpha = 0.6;
			multAlpha = 0.6;
			hitsoundDisabled = true;
			// if(ClientPrefs.data.downScroll) flipY = true;

			offsetX += width / 2;
			copyAngle = false;

			switch (noteData)
			{
				case 0:
					animation.play('purpleholdend');
				case 1:
					animation.play('blueholdend');
				case 2:
					animation.play('greenholdend');
				case 3:
					animation.play('redholdend');
			}

			updateHitbox();

			offsetX -= width / 2;

			if (PlayState.isPixelStage)
				offsetX += 30;

			if (prevNote.isSustainNote)
			{
				switch (prevNote.noteData)
				{
					case 0:
						prevNote.animation.play('purplehold');
					case 1:
						prevNote.animation.play('bluehold');
					case 2:
						prevNote.animation.play('greenhold');
					case 3:
						prevNote.animation.play('redhold');
				}

				prevNote.scale.y *= Conductor.stepCrochet / 100 * 1.05;
				if(PlayState.instance != null)
				{
					prevNote.scale.y *= PlayState.instance.songSpeed;
				}

				if(PlayState.isPixelStage) {
					prevNote.scale.y *= 1.19;
					prevNote.scale.y *= (6 / height); //Auto adjust note size
				}
				prevNote.updateHitbox();
				prevNote.baseScaleX = prevNote.scale.x;
				prevNote.baseScaleY = prevNote.scale.y;
				// prevNote.setGraphicSize();
			}

			if(PlayState.isPixelStage) {
				scale.y *= PlayState.daPixelZoom;
				updateHitbox();
			}
		} else if(!isSustainNote) {
			earlyHitMult = 1;
		}
		x += offsetX;
		baseScaleX = scale.x;
		baseScaleY = scale.y;
	}

	var lastNoteOffsetXForPixelAutoAdjusting:Float = 0;
	var lastNoteScaleToo:Float = 1;
	public var originalHeightForCalcs:Float = 6;
	public function reloadNote(?prefix:String = '', ?texture:String = '', ?suffix:String = '') {
		if(prefix == null) prefix = '';
		if(texture == null) texture = '';
		if(suffix == null) suffix = '';

		if (noteScript != null && noteScript.scriptType == 'hscript')
		{
			var noteScript:FunkinHScript = cast noteScript;
			if (noteScript.executeFunc("onReloadNote", [this, prefix, texture, suffix], this) == Globals.Function_Stop)
				return;
		}

		var skin:String = texture;
		if(texture.length < 1) {
			skin = PlayState.arrowSkins[player];
			if(skin == null || skin.length < 1) {
				skin = 'NOTE_assets';
			}
		}

		var animName:String = null;
		if(animation.curAnim != null) {
			animName = animation.curAnim.name;
		}

		var arraySkin:Array<String> = skin.split('/');
		arraySkin[arraySkin.length-1] = prefix + arraySkin[arraySkin.length-1] + suffix;

		var lastScaleY:Float = scale.y;
		var blahblah:String = arraySkin.join('/');
		isQuant = false;
		if(PlayState.isPixelStage) {
			if(isSustainNote) {
				if ((ClientPrefs.data.noteSkin == 'Quants' || ClientPrefs.data.noteSkin == "QuantStep") && canQuant){
					if(Assets.exists(Paths.getPath("images/pixelUI/QUANT" + blahblah + "ENDS.png", IMAGE)) ||
						isQuant = true;
					}
				}
				loadGraphic(Paths.image('pixelUI/' + blahblah + 'ENDS'));
				width = width / 4;
				height = height / 2;
				originalHeightForCalcs = height;
				loadGraphic(Paths.image('pixelUI/' + blahblah + 'ENDS'), true, Math.floor(width), Math.floor(height));
			} else {
				if ((ClientPrefs.data.noteSkin == 'Quants' || ClientPrefs.data.noteSkin == "QuantStep") && canQuant){
					if(Assets.exists(Paths.getPath("images/pixelUI/QUANT" + blahblah + ".png", IMAGE)) ||
						isQuant = true;
					}
				}
				loadGraphic(Paths.image('pixelUI/' + blahblah));
				width = width / 4;
				height = height / 5;
				loadGraphic(Paths.image('pixelUI/' + blahblah), true, Math.floor(width), Math.floor(height));
			}
			setGraphicSize(Std.int(width * PlayState.daPixelZoom));
			loadPixelNoteAnims();
			antialiasing = false;

			if(isSustainNote) {
				offsetX += lastNoteOffsetXForPixelAutoAdjusting;
				lastNoteOffsetXForPixelAutoAdjusting = (width - 7) * (PlayState.daPixelZoom / 2);
				offsetX -= lastNoteOffsetXForPixelAutoAdjusting;

				/*if(animName != null && !animName.endsWith('end'))
				{
					lastScaleY /= lastNoteScaleToo;
					lastNoteScaleToo = (6 / height);
					lastScaleY *= lastNoteScaleToo;
				}*/
			}
		} else {
			if ((ClientPrefs.data.noteSkin == 'Quants' || ClientPrefs.data.noteSkin == "QuantStep") && canQuant){
				if(Assets.exists(Paths.getPath("images/QUANT" + blahblah + ".png", IMAGE)) || { // this can probably only be done once and then added to some sort of cache
					// soon:tm:
					isQuant = true;
					// trace(blahblah);
				}
			}
			frames = Paths.getSparrowAtlas(blahblah);
			loadNoteAnims();
			antialiasing = ClientPrefs.data.antialiasing;
		}
		if(isSustainNote) {
			scale.y = lastScaleY;
		}
		updateHitbox();
		baseScaleX = scale.x;
		baseScaleY = scale.y;

		if(animName != null)
			animation.play(animName, true);

		if(inEditor) {
			setGraphicSize(ChartingState.GRID_SIZE, ChartingState.GRID_SIZE);
			updateHitbox();
			baseScaleX = scale.x;
			baseScaleY = scale.y;
		}

		if (noteScript != null && noteScript.scriptType == 'hscript')
		{
			var noteScript:FunkinHScript = cast noteScript;
			noteScript.executeFunc("postReloadNote", [this, prefix, texture, suffix], this);
		}
	}

	public function loadNoteAnims() {
		if (noteScript != null && noteScript.scriptType == 'hscript'){
			var noteScript:FunkinHScript = cast noteScript;
			if (noteScript.exists("loadNoteAnims") && Reflect.isFunction(noteScript.get("loadNoteAnims"))){
				noteScript.executeFunc("loadNoteAnims", [this], this, ["super" => _loadNoteAnims]);
				return;
			}
		}
		_loadNoteAnims();
	}

	public function loadPixelNoteAnims() {
		if (noteScript != null && noteScript.scriptType == 'hscript')
		{
			var noteScript:FunkinHScript = cast noteScript;
			if (noteScript.exists("loadPixelNoteAnims") && Reflect.isFunction(noteScript.get("loadNoteAnims")))
			{
				noteScript.executeFunc("loadPixelNoteAnims", [this], this, ["super" => _loadPixelNoteAnims]);
				return;
			}
		}
		_loadPixelNoteAnims();
	}

	function _loadNoteAnims()
	{
		animation.addByPrefix('greenScroll', 'green0');
		animation.addByPrefix('redScroll', 'red0');
		animation.addByPrefix('blueScroll', 'blue0');
		animation.addByPrefix('purpleScroll', 'purple0');

		if (isSustainNote)
		{
			animation.addByPrefix('purpleholdend', 'pruple end hold');
			animation.addByPrefix('greenholdend', 'green hold end');
			animation.addByPrefix('redholdend', 'red hold end');
			animation.addByPrefix('blueholdend', 'blue hold end');

			animation.addByPrefix('purplehold', 'purple hold piece');
			animation.addByPrefix('greenhold', 'green hold piece');
			animation.addByPrefix('redhold', 'red hold piece');
			animation.addByPrefix('bluehold', 'blue hold piece');
		}

		setGraphicSize(Std.int(width * 0.7));
		updateHitbox();
		baseScaleX = scale.x;
		baseScaleY = scale.y;
	}

	function _loadPixelNoteAnims(){
		if (isSustainNote)
		{
			animation.add('purpleholdend', [PURP_NOTE + 4]);
			animation.add('greenholdend', [GREEN_NOTE + 4]);
			animation.add('redholdend', [RED_NOTE + 4]);
			animation.add('blueholdend', [BLUE_NOTE + 4]);

			animation.add('purplehold', [PURP_NOTE]);
			animation.add('greenhold', [GREEN_NOTE]);
			animation.add('redhold', [RED_NOTE]);
			animation.add('bluehold', [BLUE_NOTE]);
		}
		else
		{
			animation.add('greenScroll', [GREEN_NOTE + 4]);
			animation.add('redScroll', [RED_NOTE + 4]);
			animation.add('blueScroll', [BLUE_NOTE + 4]);
			animation.add('purpleScroll', [PURP_NOTE + 4]);
		}
	}

	override function update(elapsed:Float)
	{
		super.update(elapsed);

		if(!inEditor){
			if (noteScript != null && noteScript.scriptType == 'hscript'){
				var noteScript:FunkinHScript = cast noteScript;
				noteScript.executeFunc("update", [this, elapsed], this);
			}
		}

		colorSwap.daAlpha = alphaMod * alphaMod2;

		var actualHitbox:Float = hitbox * earlyHitMult;
		/*if(mustPress){
			var diff = (strumTime-Conductor.songPosition);
			var absDiff = Math.abs(diff);
			canBeHit = absDiff<=actualHitbox;

			if (strumTime < Conductor.songPosition - Conductor.safeZoneOffset && !wasGoodHit)
				tooLate = true;
		}else{
			var diff = (strumTime-Conductor.songPosition);
			canBeHit = isSustainNote && prevNote.wasGoodHit && prevNote!=null && diff<=actualHitbox || diff<=0;
		}*/

		var diff = (strumTime - Conductor.songPosition);
		noteDiff = diff;
		var absDiff = Math.abs(diff);
		canBeHit = absDiff <= actualHitbox;
		if (hitByOpponent)wasGoodHit=true;

		if (strumTime < Conductor.songPosition - Conductor.safeZoneOffset && !wasGoodHit)
			tooLate = true;

		if (tooLate && !inEditor)
		{
			if (alpha > 0.3)
				alpha = 0.3;
		}
	}

	override public function destroy(){
		if(playField!=null)playField.remNote(this);
		
		defScale.put();
		return super.destroy();
	}
}
