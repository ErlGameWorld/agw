import React, { useState } from 'react';
import { Form, Input, Button, Card, Typography, message } from 'antd';
import { UserOutlined, TrophyOutlined } from '@ant-design/icons';

const { Title, Text } = Typography;

interface PlayerInfo {
  index: number;
  name: string;
  score: number;
  wins: number;
  losses: number;
  status: number;
}

interface LoginProps {
  onLogin: (username: string) => void;
  playerInfo?: PlayerInfo;
}

export const Login: React.FC<LoginProps> = ({ onLogin, playerInfo }) => {
  const [loading, setLoading] = useState(false);
  const [form] = Form.useForm();

  const onFinish = (values: { username: string }) => {
    if (!values.username.trim()) {
      message.error('请输入用户名');
      return;
    }
    setLoading(true);
    setTimeout(() => {
      setLoading(false);
      onLogin(values.username.trim());
    }, 300);
  };

  return (
    <div style={{ 
      position: 'fixed',
      top: 0,
      left: 0,
      right: 0,
      bottom: 0,
      display: 'flex',
      justifyContent: 'center', 
      alignItems: 'center', 
      background: 'linear-gradient(135deg, #1a1a2e 0%, #16213e 50%, #0f3460 100%)'
    }}>
      <Card style={{ 
        width: 400, 
        borderRadius: 16, 
        boxShadow: '0 20px 60px rgba(0,0,0,0.4)',
        background: 'rgba(255,255,255,0.95)'
      }}>
        <div style={{ textAlign: 'center', marginBottom: 32 }}>
          <div style={{ 
            fontSize: 64, 
            marginBottom: 16
          }}>
            🃏
          </div>
          <Title level={2} style={{ marginBottom: 8, color: '#1a1a2e' }}>斗地主</Title>
          <Text type="secondary" style={{ fontSize: 14 }}>智能AI对战系统</Text>
        </div>
        
        <Form
          form={form}
          name="login"
          onFinish={onFinish}
          layout="vertical"
        >
          <Form.Item
            name="username"
            rules={[
              { required: true, message: '请输入用户名!' },
              { min: 2, message: '用户名至少2个字符!' },
              { max: 12, message: '用户名最多12个字符!' }
            ]}
          >
            <Input 
              prefix={<UserOutlined style={{ color: '#999' }} />} 
              placeholder="请输入用户名" 
              size="large"
              maxLength={12}
              style={{ borderRadius: 8 }}
            />
          </Form.Item>

          <Form.Item>
            <Button 
              type="primary" 
              htmlType="submit" 
              size="large"
              style={{ 
                width: '100%',
                background: 'linear-gradient(135deg, #667eea 0%, #764ba2 100%)',
                border: 'none',
                borderRadius: 8,
                height: 48,
                fontSize: 16
              }} 
              loading={loading}
            >
              进入游戏
            </Button>
          </Form.Item>
        </Form>

        {playerInfo && (
          <div style={{ 
            marginTop: 24, 
            padding: 20, 
            background: 'linear-gradient(135deg, #f5f7fa 0%, #e4e8eb 100%)', 
            borderRadius: 12 
          }}>
            <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8, marginBottom: 16 }}>
              <TrophyOutlined style={{ color: '#faad14', fontSize: 18 }} />
              <Text strong style={{ fontSize: 16 }}>历史战绩</Text>
            </div>
            <div style={{ display: 'flex', justifyContent: 'space-around', textAlign: 'center' }}>
              <div>
                <div style={{ fontSize: 28, fontWeight: 'bold', color: '#52c41a' }}>{playerInfo.wins}</div>
                <div style={{ fontSize: 13, color: '#999', marginTop: 4 }}>胜场</div>
              </div>
              <div style={{ width: 1, background: '#e8e8e8' }} />
              <div>
                <div style={{ fontSize: 28, fontWeight: 'bold', color: '#ff4d4f' }}>{playerInfo.losses}</div>
                <div style={{ fontSize: 13, color: '#999', marginTop: 4 }}>败场</div>
              </div>
              <div style={{ width: 1, background: '#e8e8e8' }} />
              <div>
                <div style={{ fontSize: 28, fontWeight: 'bold', color: '#1890ff' }}>{playerInfo.score}</div>
                <div style={{ fontSize: 13, color: '#999', marginTop: 4 }}>积分</div>
              </div>
            </div>
          </div>
        )}
      </Card>
    </div>
  );
};
