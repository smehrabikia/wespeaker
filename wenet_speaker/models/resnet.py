'''ResNet in PyTorch.

Some modifications from the original architecture:
1. Smaller kernel size for the input layer
2. Smaller number of Channels
3. No max_pooling involved

Reference:
[1] Kaiming He, Xiangyu Zhang, Shaoqing Ren, Jian Sun
    Deep Residual Learning for Image Recognition. arXiv:1512.03385
'''
import torch
import torch.nn as nn
import torch.nn.functional as F
from .pooling import *

class BasicBlock(nn.Module):
    expansion = 1

    def __init__(self, in_planes, planes, stride=1):
        super(BasicBlock, self).__init__()
        self.conv1 = nn.Conv2d(in_planes, planes, kernel_size=3, stride=stride, padding=1, bias=False)
        self.bn1 = nn.BatchNorm2d(planes)
        self.conv2 = nn.Conv2d(planes, planes, kernel_size=3, stride=1, padding=1, bias=False)
        self.bn2 = nn.BatchNorm2d(planes)

        self.shortcut = nn.Sequential()
        if stride != 1 or in_planes != self.expansion*planes:
            self.shortcut = nn.Sequential(
                nn.Conv2d(in_planes, self.expansion*planes, kernel_size=1, stride=stride, bias=False),
                nn.BatchNorm2d(self.expansion*planes)
            )

    def forward(self, x):
        out = F.relu(self.bn1(self.conv1(x)))
        out = self.bn2(self.conv2(out))
        out += self.shortcut(x)
        out = F.relu(out)
        return out


class Bottleneck(nn.Module):
    expansion = 4

    def __init__(self, in_planes, planes, stride=1):
        super(Bottleneck, self).__init__()
        self.conv1 = nn.Conv2d(in_planes, planes, kernel_size=1, bias=False)
        self.bn1 = nn.BatchNorm2d(planes)
        self.conv2 = nn.Conv2d(planes, planes, kernel_size=3, stride=stride, padding=1, bias=False)
        self.bn2 = nn.BatchNorm2d(planes)
        self.conv3 = nn.Conv2d(planes, self.expansion*planes, kernel_size=1, bias=False)
        self.bn3 = nn.BatchNorm2d(self.expansion*planes)

        self.shortcut = nn.Sequential()
        if stride != 1 or in_planes != self.expansion*planes:
            self.shortcut = nn.Sequential(
                nn.Conv2d(in_planes, self.expansion*planes, kernel_size=1, stride=stride, bias=False),
                nn.BatchNorm2d(self.expansion*planes)
            )

    def forward(self, x):
        out = F.relu(self.bn1(self.conv1(x)))
        out = F.relu(self.bn2(self.conv2(out)))
        out = self.bn3(self.conv3(out))
        out += self.shortcut(x)
        out = F.relu(out)
        return out

class ResNet(nn.Module):
    def __init__(self, block, num_blocks, m_channels=32, feat_dim=40, n_stats=2, embed_dim=128):
        super(ResNet, self).__init__()
        self.in_planes = m_channels
        self.feat_dim = feat_dim
        self.embed_dim = embed_dim
        self.stats_dim = int(feat_dim/8) * m_channels * 8

        self.conv1 = nn.Conv2d(1, m_channels, kernel_size=3, stride=1, padding=1, bias=False)
        self.bn1 = nn.BatchNorm2d(m_channels)
        self.layer1 = self._make_layer(block, m_channels, num_blocks[0], stride=1)
        self.layer2 = self._make_layer(block, m_channels*2, num_blocks[1], stride=2)
        self.layer3 = self._make_layer(block, m_channels*4, num_blocks[2], stride=2)
        self.layer4 = self._make_layer(block, m_channels*8, num_blocks[3], stride=2)
        self.pool = TSTP()
        self.seg_1 = nn.Linear(self.stats_dim * n_stats * block.expansion, embed_dim)
        self.seg_bn_1 = nn.BatchNorm1d(embed_dim, affine=False)
        self.seg_2 = nn.Linear(embed_dim, embed_dim)

    def _make_layer(self, block, planes, num_blocks, stride):
        strides = [stride] + [1]*(num_blocks-1)
        layers = []
        for stride in strides:
            layers.append(block(self.in_planes, planes, stride))
            self.in_planes = planes * block.expansion
        return nn.Sequential(*layers)

    def forward(self, x):
        x = x.unsqueeze_(1)
        out = F.relu(self.bn1(self.conv1(x)))
        out = self.layer1(out)
        out = self.layer2(out)
        out = self.layer3(out)
        out = self.layer4(out)

        if isinstance(self.pool, SAP):
            stats, penalty = self.pool(out)
        else:
            stats = self.pool(out)

        embed_a = self.seg_1(stats)
        out = F.relu(embed_a)
        out = self.seg_bn_1(out)
        embed_b = self.seg_2(out)
        
        if isinstance(self.pool, SAP):
            return embed_a, embed_b, penalty
        else:
            return embed_a, embed_b


def ResNet18(feat_dim, embed_dim, n_stats=2):
    return ResNet(BasicBlock, [2,2,2,2], feat_dim=feat_dim, embed_dim=embed_dim, n_stats=n_stats)

def ResNet34(feat_dim, embed_dim, n_stats=2):
    return ResNet(BasicBlock, [3,4,6,3], feat_dim=feat_dim, embed_dim=embed_dim, n_stats=n_stats)

def ResNet50(feat_dim, embed_dim, n_stats=2):
    return ResNet(Bottleneck, [3,4,6,3], feat_dim=feat_dim, embed_dim=embed_dim, n_stats=n_stats)

def ResNet101(feat_dim, embed_dim, n_stats=2):
    return ResNet(Bottleneck, [3,4,23,3], feat_dim=feat_dim, embed_dim=embed_dim, n_stats=n_stats)

def ResNet152():
    return ResNet(Bottleneck, [3,8,36,3], feat_dim=feat_dim, embed_dim=embed_dim, n_stats=n_stats)



def test():
    net = ResNet34(40, 256, 1)
    net.pool = TAP()   
    y = net(torch.randn(10,40,200))
    print(y[0].size())

# test()
