import * as Proto from "./proto/protoMsg";

type OutgoingPayload = Record<string, unknown>;
type MessageHandler = (msg: Record<string, unknown>) => void;
type ProtoConstructor = new () => Proto.ProtoMessage;
type ProtoRegistry = Record<string, ProtoConstructor>;

export class WSClient {
    private socket: WebSocket | null = null;
    private url: string;
    private onMessage: MessageHandler;
    private reconnectAttempts: number = 0;
    private maxReconnectAttempts: number = 3;
    private reconnectDelay: number = 1000;
    private connectResolve: (() => void) | null = null;
    private connectReject: ((reason?: unknown) => void) | null = null;
    private shouldReconnect: boolean = true;
    private heartbeatTimer: number | null = null;
    private handshakeDone: boolean = false;
    private pendingMessages: OutgoingPayload[] = [];
    private lastHeartbeatTime: number = 0;
    private visibilityHandler: (() => void) | null = null;
    private static readonly HEARTBEAT_INTERVAL = 5000;
    private static readonly HEARTBEAT_DEBOUNCE = 1000; // 1秒内不重复发送
    private lastHeartbeatSendTime: number = 0;

    constructor(url: string, onMessage: MessageHandler) {
        this.url = url;
        this.onMessage = onMessage;
        this.setupVisibilityHandler();
    }

    private setupVisibilityHandler(): void {
        if (typeof document === 'undefined') {
            return;
        }
        console.log("[Heartbeat] Setting up visibility handler");
        this.visibilityHandler = () => {
            console.log(`[Heartbeat] ${this.formatTime()} Visibility changed to: ${document.visibilityState}`);
            if (document.visibilityState === 'visible') {
                console.log("[Heartbeat] Page became visible, checking heartbeat");
                this.checkAndSendHeartbeat();
            }
        };
        document.addEventListener('visibilitychange', this.visibilityHandler);
    }

    private checkAndSendHeartbeat(): void {
        const now = Date.now();
        const elapsed = now - this.lastHeartbeatTime;
        console.log(`[Heartbeat] ${this.formatTime()} checkAndSendHeartbeat called, elapsed=${elapsed}ms, interval=${WSClient.HEARTBEAT_INTERVAL}ms`);
        if (elapsed >= WSClient.HEARTBEAT_INTERVAL) {
            console.log(`[Heartbeat] ${this.formatTime()} Sending overdue heartbeat immediately`);
            this.sendHeartbeat();
        }
    }

    private createHandshakePayload(): { encrypt1: number; encrypt2: number } {
        const MAGIC_1 = 0x9E3779B9;
        const MAGIC_2 = 0x3C6EF372;
        for (let i = 0; i < 64; i += 1) {
            const encrypt1 = Math.floor(Math.random() * 0x80000000);
            const encrypt2Unsigned = ((encrypt1 ^ MAGIC_1) + MAGIC_2) >>> 0;
            if (encrypt2Unsigned <= 0x7FFFFFFF) {
                return { encrypt1, encrypt2: encrypt2Unsigned };
            }
        }
        return { encrypt1: 1, encrypt2: (((1 ^ MAGIC_1) + MAGIC_2) & 0x7FFFFFFF) >>> 0 };
    }

    private sendHandshake(): boolean {
        const payload = this.createHandshakePayload();
        const ok = this.sendRaw("cs_handshake", payload);
        if (ok) {
            console.log("Handshake sent, waiting for response");
        }
        return ok;
    }

    private formatTime(): string {
        const now = new Date();
        return now.toISOString().replace('T', ' ').substring(0, 19);
    }

    private sendHeartbeat(): void {
        const now = Date.now();
        // 防抖：1秒内不重复发送
        if (now - this.lastHeartbeatSendTime < WSClient.HEARTBEAT_DEBOUNCE) {
            console.log(`[Heartbeat] ${this.formatTime()} Heartbeat debounced, too soon`);
            return;
        }
        console.log(`[Heartbeat] ${this.formatTime()} sendHeartbeat called`);
        if (this.socket?.readyState === WebSocket.OPEN) {
            const sent = this.send({ cs_heartbeat: {} });
            if (sent) {
                this.lastHeartbeatTime = now;
                this.lastHeartbeatSendTime = now;
                console.log(`[Heartbeat] ${this.formatTime()} Heartbeat sent successfully`);
            } else {
                console.log("[Heartbeat] Heartbeat send failed");
            }
        } else {
            console.log("[Heartbeat] Socket not open, readyState:", this.socket?.readyState);
        }
    }

    private startHeartbeat(): void {
        this.stopHeartbeat();
        console.log(`[Heartbeat] ${this.formatTime()} Starting heartbeat timer`);
        this.lastHeartbeatTime = Date.now();
        
        const scheduleNext = () => {
            console.log(`[Heartbeat] ${this.formatTime()} Timer fired, scheduling next heartbeat in ${WSClient.HEARTBEAT_INTERVAL} ms`);
            this.heartbeatTimer = window.setTimeout(() => {
                console.log(`[Heartbeat] ${this.formatTime()} setTimeout callback executed`);
                if (!this.shouldReconnect) {
                    return;
                }
                this.sendHeartbeat();
                scheduleNext();
            }, WSClient.HEARTBEAT_INTERVAL);
        };
        
        scheduleNext();
    }

    private stopHeartbeat(): void {
        if (this.heartbeatTimer !== null) {
            console.log("[Heartbeat] Stopping heartbeat timer");
            window.clearTimeout(this.heartbeatTimer);
            this.heartbeatTimer = null;
        }
    }

    public connect(): Promise<void> {
        console.log("connect() called, socket state:", this.socket?.readyState, "handshakeDone:", this.handshakeDone);
        if (this.socket?.readyState === WebSocket.OPEN && this.handshakeDone) {
            console.log("Already connected and handshake done");
            return Promise.resolve();
        }
        if (this.socket?.readyState === WebSocket.OPEN && !this.handshakeDone) {
            console.log("Socket open but handshake not done, sending handshake");
            return new Promise((resolve, reject) => {
                const existingResolve = this.connectResolve;
                const existingReject = this.connectReject;
                this.connectResolve = () => {
                    existingResolve?.();
                    resolve();
                };
                this.connectReject = (reason) => {
                    existingReject?.(reason);
                    reject(reason);
                };
                this.sendHandshake();
            });
        }
        if (this.socket?.readyState === WebSocket.CONNECTING && this.connectResolve) {
            console.log("Already connecting, waiting");
            return new Promise((resolve, reject) => {
                const existingResolve = this.connectResolve;
                const existingReject = this.connectReject;
                this.connectResolve = () => {
                    existingResolve?.();
                    resolve();
                };
                this.connectReject = (reason) => {
                    existingReject?.(reason);
                    reject(reason);
                };
            });
        }
        this.shouldReconnect = true;
        return new Promise((resolve, reject) => {
            this.connectResolve = resolve;
            this.connectReject = reject;
            try {
                this.socket = new WebSocket(this.url);
                this.socket.binaryType = 'arraybuffer';
                this.handshakeDone = false;

                this.socket.onopen = () => {
                    console.log("WebSocket connected, sending handshake immediately");
                    if (!this.sendHandshake()) {
                        const reject = this.connectReject;
                        this.connectResolve = null;
                        this.connectReject = null;
                        reject?.(new Error("Failed to send handshake"));
                    }
                };

                this.socket.onmessage = (event) => {
                    try {
                        const data = new Uint8Array(event.data as ArrayBuffer);
                        const msg = Proto.MessageFactory.deserializeFromBytes(data);
                        if (msg) {
                            const msgName = Proto.ProtoMsgName[msg.msgId as keyof typeof Proto.ProtoMsgName] || '';
                            if (!msgName) {
                                console.error("Unknown message name for msgId:", msg.msgId);
                                return;
                            }
                            
                            if (msgName === 'sc_handshake') {
                                console.log("Handshake response received, connection ready");
                                this.handshakeDone = true;
                                this.flushPendingMessages();
                                this.startHeartbeat();
                                this.reconnectAttempts = 0;
                                const resolve = this.connectResolve;
                                this.connectResolve = null;
                                this.connectReject = null;
                                resolve?.();
                            }
                            
                            const wrappedMsg = { [msgName]: msg };
                            this.onMessage(wrappedMsg);
                        }
                    } catch (e) {
                        console.error("Message decode error:", e);
                    }
                };

                this.socket.onerror = (error) => {
                    console.error("WebSocket error:", error);
                    const reject = this.connectReject;
                    this.connectResolve = null;
                    this.connectReject = null;
                    reject?.(new Error("WebSocket connection error"));
                };

                this.socket.onclose = (event) => {
                    console.log("WebSocket closed:", event.code, event.reason, "wasClean:", event.wasClean);
                    this.stopHeartbeat();
                    this.socket = null;
                    this.handshakeDone = false;
                    this.pendingMessages = [];
                    const shouldRetry = this.shouldReconnect && !event.wasClean && this.reconnectAttempts < this.maxReconnectAttempts;
                    console.log("Should retry:", shouldRetry, "reconnectAttempts:", this.reconnectAttempts);
                    this.connectResolve = null;
                    this.connectReject = null;
                    if (shouldRetry) {
                        this.reconnectAttempts++;
                        console.log(`Attempting reconnect ${this.reconnectAttempts}/${this.maxReconnectAttempts} in ${this.reconnectDelay * this.reconnectAttempts}ms...`);
                        setTimeout(() => {
                            console.log("Executing reconnect...");
                            this.connect().catch((err) => {
                                console.error("Reconnect failed:", err);
                            });
                        }, this.reconnectDelay * this.reconnectAttempts);
                    }
                };
            } catch (e) {
                console.error("Failed to create WebSocket:", e);
                this.connectResolve = null;
                this.connectReject = null;
                reject(e);
            }
        });
    }

    public isConnected(): boolean {
        return this.socket !== null && this.socket.readyState === WebSocket.OPEN && this.handshakeDone;
    }

    private sendRaw(msgName: string, msgData: unknown): boolean {
        if (!this.socket || this.socket.readyState !== WebSocket.OPEN) {
            console.error("WebSocket not connected, readyState:", this.socket?.readyState);
            return false;
        }

        console.log(`Sending message: ${msgName}`, msgData);

        try {
            const ProtoClass = (Proto as unknown as ProtoRegistry)[msgName];
            if (!ProtoClass) {
                console.error(`Unknown message type: ${msgName}`);
                return false;
            }

            const instance = new ProtoClass();
            Object.assign(instance, msgData);
            
            const bin = Proto.MessageFactory.serializeToBytes(instance);
            console.log(`Serialized ${msgName} to ${bin.length} bytes`);
            
            this.socket.send(bin);
            return true;
        } catch (e) {
            console.error(`Failed to serialize/send ${msgName}:`, e);
            return false;
        }
    }

    private flushPendingMessages(): void {
        if (!this.handshakeDone || this.pendingMessages.length === 0) {
            return;
        }
        const queued = this.pendingMessages;
        this.pendingMessages = [];
        queued.forEach((payload) => {
            const [msgName] = Object.keys(payload);
            if (!msgName) {
                return;
            }
            this.sendRaw(msgName, payload[msgName]);
        });
    }

    public send(msg: OutgoingPayload): boolean {
        const keys = Object.keys(msg);
        if (keys.length === 0) {
            console.error("Empty message");
            return false;
        }
        const msgName = keys[0];
        const msgData = msg[msgName];
        if (msgName !== "cs_handshake" && !this.handshakeDone) {
            if (this.socket?.readyState === WebSocket.OPEN) {
                this.pendingMessages.push(msg);
                console.log(`Queued message before handshake: ${msgName}`);
                return true;
            }
            console.error("WebSocket not ready for message, readyState:", this.socket?.readyState);
            return false;
        }
        return this.sendRaw(msgName, msgData);
    }

    public disconnect(): void {
        console.log("disconnect() called");
        this.shouldReconnect = false;
        this.stopHeartbeat();
        this.handshakeDone = false;
        this.pendingMessages = [];
        if (this.visibilityHandler && typeof document !== 'undefined') {
            document.removeEventListener('visibilitychange', this.visibilityHandler);
            this.visibilityHandler = null;
        }
        this.connectResolve = null;
        this.connectReject = null;
        if (this.socket) {
            this.socket.close(1000, "Client disconnect");
            this.socket = null;
        }
    }
}
