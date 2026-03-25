const textEncoder = new TextEncoder();
const textDecoder = new TextDecoder();

export class ByteArray {
    private buffer: Uint8Array;
    private view: DataView;
    private position: number = 0;
    private capacity: number;

    constructor(initialCapacity: number = 2048) {
        this.capacity = initialCapacity;
        this.buffer = new Uint8Array(initialCapacity);
        this.view = new DataView(this.buffer.buffer);
    }

    private ensureCapacity(bytes: number): void {
        if (this.position + bytes > this.capacity) {
            let newCapacity = this.capacity * 2;
            while (this.position + bytes > newCapacity) {
                newCapacity *= 2;
            }
            const newBuffer = new Uint8Array(newCapacity);
            newBuffer.set(this.buffer);
            this.buffer = newBuffer;
            this.view = new DataView(this.buffer.buffer);
            this.capacity = newCapacity;
        }
    }

    private checkAvailable(bytes: number): void {
        if (this.position + bytes > this.buffer.length) {
            throw new Error(`Buffer underflow: need ${bytes} bytes, available ${this.buffer.length - this.position}`);
        }
    }

    public write_bool(value: boolean): void {
        this.ensureCapacity(1);
        this.buffer[this.position++] = value ? 1 : 0;
    }

    public write_int8(value: number): void {
        if (value < -128 || value > 127) {
            throw new Error(`int8 value out of range: ${value}`);
        }
        this.ensureCapacity(1);
        this.view.setInt8(this.position++, value);
    }

    public write_uint8(value: number): void {
        if (value < 0 || value > 255) {
            throw new Error(`uint8 value out of range: ${value}`);
        }
        this.ensureCapacity(1);
        this.buffer[this.position++] = value;
    }

    public write_int16(value: number): void {
        if (value < -32768 || value > 32767) {
            throw new Error(`int16 value out of range: ${value}`);
        }
        this.ensureCapacity(2);
        this.view.setInt16(this.position, value, false); // big endian
        this.position += 2;
    }

    public write_uint16(value: number): void {
        if (value < 0 || value > 65535) {
            throw new Error(`uint16 value out of range: ${value}`);
        }
        this.ensureCapacity(2);
        this.view.setUint16(this.position, value, false);
        this.position += 2;
    }

    public write_int32(value: number): void {
        if (value < -2147483648 || value > 2147483647) {
            throw new Error(`int32 value out of range: ${value}`);
        }
        this.ensureCapacity(4);
        this.view.setInt32(this.position, value, false);
        this.position += 4;
    }

    public write_uint32(value: number): void {
        if (value < 0 || value > 4294967295) {
            throw new Error(`uint32 value out of range: ${value}`);
        }
        this.ensureCapacity(4);
        this.view.setUint32(this.position, value, false);
        this.position += 4;
    }

    public write_int64(value: bigint): void {
        this.ensureCapacity(8);
        this.view.setBigInt64(this.position, value, false);
        this.position += 8;
    }

    public write_uint64(value: bigint): void {
        this.ensureCapacity(8);
        this.view.setBigUint64(this.position, value, false);
        this.position += 8;
    }

    public write_float(value: number): void {
        if (isNaN(value) || !isFinite(value)) {
            throw new Error(`Invalid float value: ${value}`);
        }
        this.ensureCapacity(4);
        this.view.setFloat32(this.position, value, false);
        this.position += 4;
    }

    public write_double(value: number): void {
        if (isNaN(value) || !isFinite(value)) {
            throw new Error(`Invalid double value: ${value}`);
        }
        this.ensureCapacity(8);
        this.view.setFloat64(this.position, value, false);
        this.position += 8;
    }

    public write_string(value: string): void {
        if (!value) value = '';
        
        const maxLength = value.length * 4;
        this.ensureCapacity(maxLength + 2);
        
        const lengthPos = this.position;
        this.position += 2;
        
        const result = textEncoder.encodeInto(value, this.buffer.subarray(this.position));
        const written = result.written || 0;
        
        if (written > 65535) {
            throw new Error(`String too long: ${written} bytes (max: 65535)`);
        }
        
        this.view.setUint16(lengthPos, written, false);
        this.position += written;
    }

    public write_integer(value: number): void {
        if (!Number.isInteger(value)) {
            throw new Error(`write_integer: value must be an integer, got ${value}`);
        }
        if (value >= -128 && value <= 127) {
            this.write_uint8(8);
            this.write_int8(value);
        } else if (value >= -32768 && value <= 32767) {
            this.write_uint8(16);
            this.write_int16(value);
        } else if (value >= -2147483648 && value <= 2147483647) {
            this.write_uint8(32);
            this.write_int32(value);
        } else {
            this.write_uint8(64);
            this.write_int64(BigInt(value));
        }
    }

    public write_number(value: number): void {
        if (Number.isInteger(value)) {
            this.write_integer(value);
        } else {
            if (Math.fround(value) === value) {
                this.write_uint8(33);
                this.write_float(value);
            } else {
                this.write_uint8(65);
                this.write_double(value);
            }
        }
    }

    public read_bool(): boolean {
        this.checkAvailable(1);
        return this.buffer[this.position++] !== 0;
    }

    public read_int8(): number {
        this.checkAvailable(1);
        return this.view.getInt8(this.position++);
    }

    public read_uint8(): number {
        this.checkAvailable(1);
        return this.buffer[this.position++];
    }

    public read_int16(): number {
        this.checkAvailable(2);
        const value = this.view.getInt16(this.position, false);
        this.position += 2;
        return value;
    }

    public read_uint16(): number {
        this.checkAvailable(2);
        const value = this.view.getUint16(this.position, false);
        this.position += 2;
        return value;
    }

    public read_int32(): number {
        this.checkAvailable(4);
        const value = this.view.getInt32(this.position, false);
        this.position += 4;
        return value;
    }

    public read_uint32(): number {
        this.checkAvailable(4);
        const value = this.view.getUint32(this.position, false);
        this.position += 4;
        return value;
    }

    public read_int64(): bigint {
        this.checkAvailable(8);
        const value = this.view.getBigInt64(this.position, false);
        this.position += 8;
        return value;
    }

    public read_uint64(): bigint {
        this.checkAvailable(8);
        const value = this.view.getBigUint64(this.position, false);
        this.position += 8;
        return value;
    }

    public read_float(): number {
        this.checkAvailable(4);
        const value = this.view.getFloat32(this.position, false);
        this.position += 4;
        return value;
    }

    public read_double(): number {
        this.checkAvailable(8);
        const value = this.view.getFloat64(this.position, false);
        this.position += 8;
        return value;
    }

    public read_string(): string {
        const length = this.read_uint16();
        this.checkAvailable(length);

        const str = textDecoder.decode(this.buffer.subarray(this.position, this.position + length));
        this.position += length;
        return str;
    }

    public read_integer(): number {
        const tag = this.read_uint8();
        switch (tag) {
            case 8: return this.read_int8();
            case 16: return this.read_int16();
            case 32: return this.read_int32();
            case 64: return Number(this.read_int64());
            default: throw new Error(`Unknown integer tag: ${tag}`);
        }
    }

    public read_number(): number {
        const tag = this.read_uint8();
        switch (tag) {
            case 8: return this.read_int8();
            case 16: return this.read_int16();
            case 32: return this.read_int32();
            case 64: return Number(this.read_int64());
            case 33: return this.read_float();
            case 65: return this.read_double();
            default: throw new Error(`Invalid number tag: ${tag}`);
        }
    }

    public write_list<T>(list: T[] | null | undefined, writer: (val: T) => void): void {
        if (!list) {
            this.write_uint16(0);
            return;
        }
        const length = list.length;
        if (length > 65535) {
            throw new Error(`List too long: ${length} (max: 65535)`);
        }
        this.write_uint16(length);
        for (let i = 0; i < length; i++) {
            writer(list[i]);
        }
    }

    public read_list<T>(reader: () => T): T[] {
        const length = this.read_uint16();
        const list = new Array<T>(length);
        for (let i = 0; i < length; i++) {
            list[i] = reader();
        }
        return list;
    }

    public getBytes(): Uint8Array {
        return this.buffer.slice(0, this.position);
    }

    public getBytesAsArray(): number[] {
        return Array.from(this.buffer.subarray(0, this.position));
    }

    public setBytes(bytes: Uint8Array | number[], copy: boolean = false): void {
        if (bytes instanceof Uint8Array) {
            if (copy) {
                this.buffer = new Uint8Array(bytes.length);
                this.buffer.set(bytes);
            } else {
                this.buffer = bytes;
            }
            this.capacity = bytes.length;
        } else {
            this.buffer = new Uint8Array(bytes);
            this.capacity = bytes.length;
        }
        this.view = new DataView(this.buffer.buffer, this.buffer.byteOffset, this.buffer.byteLength);
        this.position = 0;
    }
}

export interface ProtoMessage {
    msgId: number;
    encode(byteArray: ByteArray): void;
    decode(byteArray: ByteArray): void;
}

export class playerInfo {
	public static readonly PROTO_ID = 1;
	public msgId: number = 1;
		public index: number = 0;
		public name: string = "";
		public score: number = 0;
		public wins: number = 0;
		public losses: number = 0;
		public status: number = 0;

	public encode(byteArray: ByteArray): void {
			byteArray.write_int32(this.index);
			byteArray.write_string(this.name);
			byteArray.write_int32(this.score);
			byteArray.write_int32(this.wins);
			byteArray.write_int32(this.losses);
			byteArray.write_int32(this.status);
	}

	public decode(byteArray: ByteArray): void {
			this.index = byteArray.read_int32();
			this.name = byteArray.read_string();
			this.score = byteArray.read_int32();
			this.wins = byteArray.read_int32();
			this.losses = byteArray.read_int32();
			this.status = byteArray.read_int32();
	}
}

export class roomInfo {
	public static readonly PROTO_ID = 2;
	public msgId: number = 2;
		public roomId: string = "";
		public name: string = "";
		public playerCount: number = 0;
		public status: number = 0;

	public encode(byteArray: ByteArray): void {
			byteArray.write_string(this.roomId);
			byteArray.write_string(this.name);
			byteArray.write_int32(this.playerCount);
			byteArray.write_int32(this.status);
	}

	public decode(byteArray: ByteArray): void {
			this.roomId = byteArray.read_string();
			this.name = byteArray.read_string();
			this.playerCount = byteArray.read_int32();
			this.status = byteArray.read_int32();
	}
}

export class card {
	public static readonly PROTO_ID = 3;
	public msgId: number = 3;
		public suit: number = 0;
		public value: number = 0;

	public encode(byteArray: ByteArray): void {
			byteArray.write_int32(this.suit);
			byteArray.write_int32(this.value);
	}

	public decode(byteArray: ByteArray): void {
			this.suit = byteArray.read_int32();
			this.value = byteArray.read_int32();
	}
}

export class scoreInfo {
	public static readonly PROTO_ID = 4;
	public msgId: number = 4;
		public index: number = 0;
		public name: string = "";
		public score: number = 0;
		public result: string = "";

	public encode(byteArray: ByteArray): void {
			byteArray.write_int32(this.index);
			byteArray.write_string(this.name);
			byteArray.write_int32(this.score);
			byteArray.write_string(this.result);
	}

	public decode(byteArray: ByteArray): void {
			this.index = byteArray.read_int32();
			this.name = byteArray.read_string();
			this.score = byteArray.read_int32();
			this.result = byteArray.read_string();
	}
}

export class sc_error {
	public static readonly PROTO_ID = 5;
	public msgId: number = 5;
		public code: number = 0;
		public msg: string = "";

	public encode(byteArray: ByteArray): void {
			byteArray.write_int32(this.code);
			byteArray.write_string(this.msg);
	}

	public decode(byteArray: ByteArray): void {
			this.code = byteArray.read_int32();
			this.msg = byteArray.read_string();
	}
}

export class cs_handshake {
	public static readonly PROTO_ID = 1001;
	public msgId: number = 1001;
		public encrypt1: number = 0;
		public encrypt2: number = 0;

	public encode(byteArray: ByteArray): void {
			byteArray.write_int32(this.encrypt1);
			byteArray.write_int32(this.encrypt2);
	}

	public decode(byteArray: ByteArray): void {
			this.encrypt1 = byteArray.read_int32();
			this.encrypt2 = byteArray.read_int32();
	}
}

export class sc_handshake {
	public static readonly PROTO_ID = 1002;
	public msgId: number = 1002;
		public result: number = 0;

	public encode(byteArray: ByteArray): void {
			byteArray.write_int32(this.result);
	}

	public decode(byteArray: ByteArray): void {
			this.result = byteArray.read_int32();
	}
}

export class cs_heartbeat {
	public static readonly PROTO_ID = 1003;
	public msgId: number = 1003;

	public encode(byteArray: ByteArray): void {
			void byteArray;
	}

	public decode(byteArray: ByteArray): void {
			void byteArray;
	}
}

export class sc_heartbeat {
	public static readonly PROTO_ID = 1004;
	public msgId: number = 1004;

	public encode(byteArray: ByteArray): void {
			void byteArray;
	}

	public decode(byteArray: ByteArray): void {
			void byteArray;
	}
}

export class cs_login {
	public static readonly PROTO_ID = 1005;
	public msgId: number = 1005;
		public name: string = "";

	public encode(byteArray: ByteArray): void {
			byteArray.write_string(this.name);
	}

	public decode(byteArray: ByteArray): void {
			this.name = byteArray.read_string();
	}
}

export class sc_login {
	public static readonly PROTO_ID = 1006;
	public msgId: number = 1006;
		public result: number = 0;
		public playerId: string = "";
		public player: playerInfo | null = null;

	public encode(byteArray: ByteArray): void {
			byteArray.write_int32(this.result);
			byteArray.write_string(this.playerId);
			if (this.player) {
				byteArray.write_uint8(1);
				this.player.encode(byteArray);
			} else {
				byteArray.write_uint8(0);
			}
	}

	public decode(byteArray: ByteArray): void {
			this.result = byteArray.read_int32();
			this.playerId = byteArray.read_string();
			const hasplayer = byteArray.read_uint8() > 0;
			if (hasplayer) {
				this.player = new playerInfo();
				this.player.decode(byteArray);
			} else {
				this.player = null;
			}
	}
}

export class cs_list_rooms {
	public static readonly PROTO_ID = 2001;
	public msgId: number = 2001;

	public encode(byteArray: ByteArray): void {
			void byteArray;
	}

	public decode(byteArray: ByteArray): void {
			void byteArray;
	}
}

export class sc_list_rooms {
	public static readonly PROTO_ID = 2002;
	public msgId: number = 2002;
		public rooms: roomInfo[] = [];

	public encode(byteArray: ByteArray): void {
			byteArray.write_list(this.rooms, (item) => item.encode(byteArray));
	}

	public decode(byteArray: ByteArray): void {
			this.rooms = byteArray.read_list(() => {
				const item = new roomInfo();
				item.decode(byteArray);
				return item;
			});
	}
}

export class cs_create_room {
	public static readonly PROTO_ID = 2003;
	public msgId: number = 2003;
		public name: string = "";

	public encode(byteArray: ByteArray): void {
			byteArray.write_string(this.name);
	}

	public decode(byteArray: ByteArray): void {
			this.name = byteArray.read_string();
	}
}

export class sc_room_update {
	public static readonly PROTO_ID = 2004;
	public msgId: number = 2004;
		public roomId: string = "";
		public status: number = 0;
		public players: playerInfo[] = [];

	public encode(byteArray: ByteArray): void {
			byteArray.write_string(this.roomId);
			byteArray.write_int32(this.status);
			byteArray.write_list(this.players, (item) => item.encode(byteArray));
	}

	public decode(byteArray: ByteArray): void {
			this.roomId = byteArray.read_string();
			this.status = byteArray.read_int32();
			this.players = byteArray.read_list(() => {
				const item = new playerInfo();
				item.decode(byteArray);
				return item;
			});
	}
}

export class cs_join_room {
	public static readonly PROTO_ID = 2005;
	public msgId: number = 2005;
		public roomId: string = "";

	public encode(byteArray: ByteArray): void {
			byteArray.write_string(this.roomId);
	}

	public decode(byteArray: ByteArray): void {
			this.roomId = byteArray.read_string();
	}
}

export class cs_leave_room {
	public static readonly PROTO_ID = 2006;
	public msgId: number = 2006;
		public roomId: string = "";

	public encode(byteArray: ByteArray): void {
			byteArray.write_string(this.roomId);
	}

	public decode(byteArray: ByteArray): void {
			this.roomId = byteArray.read_string();
	}
}

export class cs_quick_match {
	public static readonly PROTO_ID = 2007;
	public msgId: number = 2007;

	public encode(byteArray: ByteArray): void {
			void byteArray;
	}

	public decode(byteArray: ByteArray): void {
			void byteArray;
	}
}

export class cs_add_ai {
	public static readonly PROTO_ID = 2008;
	public msgId: number = 2008;

	public encode(byteArray: ByteArray): void {
			void byteArray;
	}

	public decode(byteArray: ByteArray): void {
			void byteArray;
	}
}

export class sc_ai_added {
	public static readonly PROTO_ID = 2009;
	public msgId: number = 2009;
		public name: string = "";
		public index: number = 0;

	public encode(byteArray: ByteArray): void {
			byteArray.write_string(this.name);
			byteArray.write_int32(this.index);
	}

	public decode(byteArray: ByteArray): void {
			this.name = byteArray.read_string();
			this.index = byteArray.read_int32();
	}
}

export class cs_game_start {
	public static readonly PROTO_ID = 2010;
	public msgId: number = 2010;

	public encode(byteArray: ByteArray): void {
			void byteArray;
	}

	public decode(byteArray: ByteArray): void {
			void byteArray;
	}
}

export class sc_game_start {
	public static readonly PROTO_ID = 2011;
	public msgId: number = 2011;
		public cards: card[] = [];
		public firstBidder: number = 0;

	public encode(byteArray: ByteArray): void {
			byteArray.write_list(this.cards, (item) => item.encode(byteArray));
			byteArray.write_int32(this.firstBidder);
	}

	public decode(byteArray: ByteArray): void {
			this.cards = byteArray.read_list(() => {
				const item = new card();
				item.decode(byteArray);
				return item;
			});
			this.firstBidder = byteArray.read_int32();
	}
}

export class cs_bid {
	public static readonly PROTO_ID = 2012;
	public msgId: number = 2012;
		public score: number = 0;

	public encode(byteArray: ByteArray): void {
			byteArray.write_int32(this.score);
	}

	public decode(byteArray: ByteArray): void {
			this.score = byteArray.read_int32();
	}
}

export class sc_bid_made {
	public static readonly PROTO_ID = 2013;
	public msgId: number = 2013;
		public playerIdx: number = 0;
		public score: number = 0;

	public encode(byteArray: ByteArray): void {
			byteArray.write_int32(this.playerIdx);
			byteArray.write_int32(this.score);
	}

	public decode(byteArray: ByteArray): void {
			this.playerIdx = byteArray.read_int32();
			this.score = byteArray.read_int32();
	}
}

export class sc_turn_to_bid {
	public static readonly PROTO_ID = 2014;
	public msgId: number = 2014;
		public nextTurn: number = 0;
		public currentBids: number[] = [];

	public encode(byteArray: ByteArray): void {
			byteArray.write_int32(this.nextTurn);
			byteArray.write_list(this.currentBids, (item) => byteArray.write_int32(item));
	}

	public decode(byteArray: ByteArray): void {
			this.nextTurn = byteArray.read_int32();
			this.currentBids = byteArray.read_list(() => byteArray.read_int32());
	}
}

export class cs_play {
	public static readonly PROTO_ID = 2015;
	public msgId: number = 2015;
		public cards: card[] = [];

	public encode(byteArray: ByteArray): void {
			byteArray.write_list(this.cards, (item) => item.encode(byteArray));
	}

	public decode(byteArray: ByteArray): void {
			this.cards = byteArray.read_list(() => {
				const item = new card();
				item.decode(byteArray);
				return item;
			});
	}
}

export class sc_player_played {
	public static readonly PROTO_ID = 2016;
	public msgId: number = 2016;
		public playerIdx: number = 0;
		public cards: card[] = [];

	public encode(byteArray: ByteArray): void {
			byteArray.write_int32(this.playerIdx);
			byteArray.write_list(this.cards, (item) => item.encode(byteArray));
	}

	public decode(byteArray: ByteArray): void {
			this.playerIdx = byteArray.read_int32();
			this.cards = byteArray.read_list(() => {
				const item = new card();
				item.decode(byteArray);
				return item;
			});
	}
}

export class cs_pass {
	public static readonly PROTO_ID = 2017;
	public msgId: number = 2017;

	public encode(byteArray: ByteArray): void {
			void byteArray;
	}

	public decode(byteArray: ByteArray): void {
			void byteArray;
	}
}

export class sc_player_passed {
	public static readonly PROTO_ID = 2018;
	public msgId: number = 2018;
		public playerIdx: number = 0;

	public encode(byteArray: ByteArray): void {
			byteArray.write_int32(this.playerIdx);
	}

	public decode(byteArray: ByteArray): void {
			this.playerIdx = byteArray.read_int32();
	}
}

export class cs_play_hint {
	public static readonly PROTO_ID = 2019;
	public msgId: number = 2019;

	public encode(byteArray: ByteArray): void {
			void byteArray;
	}

	public decode(byteArray: ByteArray): void {
			void byteArray;
	}
}

export class sc_play_hint {
	public static readonly PROTO_ID = 2020;
	public msgId: number = 2020;
		public cards: card[] = [];

	public encode(byteArray: ByteArray): void {
			byteArray.write_list(this.cards, (item) => item.encode(byteArray));
	}

	public decode(byteArray: ByteArray): void {
			this.cards = byteArray.read_list(() => {
				const item = new card();
				item.decode(byteArray);
				return item;
			});
	}
}

export class sc_turn_to_play {
	public static readonly PROTO_ID = 2021;
	public msgId: number = 2021;
		public nextTurn: number = 0;
		public lastPlay: card[] = [];

	public encode(byteArray: ByteArray): void {
			byteArray.write_int32(this.nextTurn);
			byteArray.write_list(this.lastPlay, (item) => item.encode(byteArray));
	}

	public decode(byteArray: ByteArray): void {
			this.nextTurn = byteArray.read_int32();
			this.lastPlay = byteArray.read_list(() => {
				const item = new card();
				item.decode(byteArray);
				return item;
			});
	}
}

export class sc_landlord_selected {
	public static readonly PROTO_ID = 2022;
	public msgId: number = 2022;
		public landlordIdx: number = 0;
		public landlordCards: card[] = [];
		public baseScore: number = 0;

	public encode(byteArray: ByteArray): void {
			byteArray.write_int32(this.landlordIdx);
			byteArray.write_list(this.landlordCards, (item) => item.encode(byteArray));
			byteArray.write_int32(this.baseScore);
	}

	public decode(byteArray: ByteArray): void {
			this.landlordIdx = byteArray.read_int32();
			this.landlordCards = byteArray.read_list(() => {
				const item = new card();
				item.decode(byteArray);
				return item;
			});
			this.baseScore = byteArray.read_int32();
	}
}

export class sc_game_over {
	public static readonly PROTO_ID = 2023;
	public msgId: number = 2023;
		public winnerIdx: number = 0;
		public scores: scoreInfo[] = [];

	public encode(byteArray: ByteArray): void {
			byteArray.write_int32(this.winnerIdx);
			byteArray.write_list(this.scores, (item) => item.encode(byteArray));
	}

	public decode(byteArray: ByteArray): void {
			this.winnerIdx = byteArray.read_int32();
			this.scores = byteArray.read_list(() => {
				const item = new scoreInfo();
				item.decode(byteArray);
				return item;
			});
	}
}

export class cs_ready {
	public static readonly PROTO_ID = 2024;
	public msgId: number = 2024;
		public ready: number = 0;

	public encode(byteArray: ByteArray): void {
			byteArray.write_int32(this.ready);
	}

	public decode(byteArray: ByteArray): void {
			this.ready = byteArray.read_int32();
	}
}

export class sc_player_ready {
	public static readonly PROTO_ID = 2025;
	public msgId: number = 2025;
		public playerIdx: number = 0;
		public ready: number = 0;
		public allReady: number = 0;

	public encode(byteArray: ByteArray): void {
			byteArray.write_int32(this.playerIdx);
			byteArray.write_int32(this.ready);
			byteArray.write_int32(this.allReady);
	}

	public decode(byteArray: ByteArray): void {
			this.playerIdx = byteArray.read_int32();
			this.ready = byteArray.read_int32();
			this.allReady = byteArray.read_int32();
	}
}


export const ProtoMsgName = {
	1: 'playerInfo',
	2: 'roomInfo',
	3: 'card',
	4: 'scoreInfo',
	5: 'sc_error',
	1001: 'cs_handshake',
	1002: 'sc_handshake',
	1003: 'cs_heartbeat',
	1004: 'sc_heartbeat',
	1005: 'cs_login',
	1006: 'sc_login',
	2001: 'cs_list_rooms',
	2002: 'sc_list_rooms',
	2003: 'cs_create_room',
	2004: 'sc_room_update',
	2005: 'cs_join_room',
	2006: 'cs_leave_room',
	2007: 'cs_quick_match',
	2008: 'cs_add_ai',
	2009: 'sc_ai_added',
	2010: 'cs_game_start',
	2011: 'sc_game_start',
	2012: 'cs_bid',
	2013: 'sc_bid_made',
	2014: 'sc_turn_to_bid',
	2015: 'cs_play',
	2016: 'sc_player_played',
	2017: 'cs_pass',
	2018: 'sc_player_passed',
	2019: 'cs_play_hint',
	2020: 'sc_play_hint',
	2021: 'sc_turn_to_play',
	2022: 'sc_landlord_selected',
	2023: 'sc_game_over',
	2024: 'cs_ready',
	2025: 'sc_player_ready',
};

export class MessageFactory {
	private static readonly messageConstructors: Record<number, new () => ProtoMessage> = {
		1: playerInfo,
		2: roomInfo,
		3: card,
		4: scoreInfo,
		5: sc_error,
		1001: cs_handshake,
		1002: sc_handshake,
		1003: cs_heartbeat,
		1004: sc_heartbeat,
		1005: cs_login,
		1006: sc_login,
		2001: cs_list_rooms,
		2002: sc_list_rooms,
		2003: cs_create_room,
		2004: sc_room_update,
		2005: cs_join_room,
		2006: cs_leave_room,
		2007: cs_quick_match,
		2008: cs_add_ai,
		2009: sc_ai_added,
		2010: cs_game_start,
		2011: sc_game_start,
		2012: cs_bid,
		2013: sc_bid_made,
		2014: sc_turn_to_bid,
		2015: cs_play,
		2016: sc_player_played,
		2017: cs_pass,
		2018: sc_player_passed,
		2019: cs_play_hint,
		2020: sc_play_hint,
		2021: sc_turn_to_play,
		2022: sc_landlord_selected,
		2023: sc_game_over,
		2024: cs_ready,
		2025: sc_player_ready,
	};

	public static deserializeFromBytes(data: Uint8Array | number[]): ProtoMessage {
		const byteArray = new ByteArray();
		byteArray.setBytes(data, false);
		const msgId = byteArray.read_uint16();
		const Constructor = MessageFactory.messageConstructors[msgId];
		if (!Constructor) {
			throw new Error(`Unknown message ID: ${msgId}`);
		}
		const instance = new Constructor();
		instance.decode(byteArray);
		return instance;
	}

	public static serializeToBytes(message: ProtoMessage): Uint8Array {
		const byteArray = new ByteArray();
		byteArray.write_uint16(message.msgId);
		message.encode(byteArray);
		return byteArray.getBytes();
	}
}
